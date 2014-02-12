#import "QSObject_Pasteboard.h"
#import "QSTypes.h"
#import "QSObject_FileHandling.h"
#import "QSObject_StringHandling.h"

NSString *QSPasteboardObjectIdentifier = @"QSObjectID";
NSString *QSPasteboardObjectAddress = @"QSObjectAddress";

#define QSPasteboardIgnoredTypes [NSArray arrayWithObjects:QSPasteboardObjectAddress, @"CorePasteboardFlavorType 0x4D555246", @"CorePasteboardFlavorType 0x54455854", nil]

id objectForPasteboardType(NSPasteboard *pasteboard, NSString *type) {
	if ([PLISTTYPES containsObject:type]) {
		return [pasteboard propertyListForType:type];
	} else if ([NSStringPboardType isEqualToString:type] || UTTypeConformsTo((__bridge CFStringRef)type, kUTTypeText) || [type hasPrefix:@"QSObject"]) {
		return [pasteboard stringForType:type];
	}else if ([NSURLPboardType isEqualToString:type]) {
		return [[NSURL URLFromPasteboard:pasteboard] absoluteString];
    } else if ([(__bridge NSString *)kUTTypeFileURL isEqualToString:type]) {
        return [NSURL URLFromPasteboard:pasteboard];
    } else if ([NSColorPboardType isEqualToString:type]) {
		return [NSKeyedArchiver archivedDataWithRootObject:[NSColor colorFromPasteboard:pasteboard]];
	} else if ([NSFileContentsPboardType isEqualToString:type]);
	else {
		return [pasteboard dataForType:type];
    }
	return nil;
}

// writes the selected data to the general pasteboard
bool writeObjectToPasteboard(NSPasteboard *pasteboard, NSString *type, id data) {
	if ([NSURLPboardType isEqualToString:type]) {
		[pasteboard addTypes:[NSArray arrayWithObjects:NSURLPboardType, NSStringPboardType, nil] owner:nil];
		[pasteboard setString:([data hasPrefix:@"mailto:"]) ?[data substringFromIndex:7] :data forType:NSStringPboardType];
		[pasteboard setString:[data URLDecoding] forType:NSURLPboardType];
	} else if ([PLISTTYPES containsObject:type] || [data isKindOfClass:[NSDictionary class]] || [data isKindOfClass:[NSArray class]])
		[pasteboard setPropertyList:data forType:type];
	else if ([data isKindOfClass:[NSString class]])
		[pasteboard setString:data forType:type];
	else if ([NSColorPboardType isEqualToString:type])
		[data writeToPasteboard:pasteboard];
	else if ([NSFileContentsPboardType isEqualToString:type]);
	else
		[pasteboard setData:data forType:type];
	return YES;
}

@implementation QSObject (Pasteboard)
+ (id)objectWithPasteboard:(NSPasteboard *)pasteboard {
	id theObject = nil;

	if ([pasteboard isTransient] || [pasteboard isAutoGenerated])
		return nil;

	if ([[pasteboard types] containsObject:QSPasteboardObjectIdentifier])
		theObject = [QSLib objectWithIdentifier:[pasteboard stringForType:QSPasteboardObjectIdentifier]];

	if (!theObject && [[pasteboard types] containsObject:QSPasteboardObjectAddress]) {
        theObject = QSLib.pasteboardObject;
	}
    
    if (theObject) {
        return theObject;
    }
	return [[QSObject alloc] initWithPasteboard:pasteboard];
}

- (id)initWithPasteboard:(NSPasteboard *)pasteboard {
	return [self initWithPasteboard:pasteboard types:nil];
}

- (void)addContentsOfClipping:(NSString *)path { // Not thread safe?
	NSPasteboard *pasteboard = [NSPasteboard pasteboardByFilteringClipping:path];
	[self addContentsOfPasteboard:pasteboard types:nil];
	[pasteboard releaseGlobally];
}

- (void)addContentsOfPasteboard:(NSPasteboard *)pasteboard types:(NSArray *)types {
	NSMutableArray *typeArray = [NSMutableArray arrayWithCapacity:1];
	for(NSString *thisType in (types?types:[pasteboard types])) {
		if ([[pasteboard types] containsObject:thisType] && ![QSPasteboardIgnoredTypes containsObject:thisType]) {
			id theObject = objectForPasteboardType(pasteboard, thisType);
			if (theObject && thisType) {
				[self setObject:theObject forType:thisType];
            } else {
				NSLog(@"bad data for %@", thisType);
            }
			[typeArray addObject:[thisType decodedPasteboardType]];
		}
	}
}

- (id)initWithPasteboard:(NSPasteboard *)pasteboard types:(NSArray *)types {
	if (self = [self init]) {

		NSString *source = nil;
        NSString *sourceApp = nil;
        NSRunningApplication *currApp = [[NSWorkspace sharedWorkspace] frontmostApplication];
		if (pasteboard == [NSPasteboard generalPasteboard]) {
			source = [currApp bundleIdentifier];
            sourceApp = [currApp localizedName];
        } else {
            source =  @"Clipboard";
            sourceApp = source;
        }

		[self setDataDictionary:[NSMutableDictionary dictionaryWithCapacity:[[pasteboard types] count]]];
		[self addContentsOfPasteboard:pasteboard types:types];

		[self setObject:source forMeta:kQSObjectSource];
		[self setObject:[NSDate date] forMeta:kQSObjectCreationDate];

		id value;
		if (value = [self objectForType:NSRTFPboardType]) {
			value = [[NSAttributedString alloc] initWithRTF:value documentAttributes:nil];
			[self setObject:[value string] forType:QSTextType];
		}
        if ([self objectForType:(__bridge NSString *)kUTTypeFileURL]) {
            [self setObject:[(NSURL *)[self objectForType:(__bridge NSString *)kUTTypeFileURL] path] forType:QSFilePathType];
        }
		if ([self objectForType:QSTextType])
			[self sniffString];
		NSString *clippingPath = [self singleFilePath];
		if (clippingPath) {
			NSString *type = [[NSFileManager defaultManager] typeOfFile:clippingPath];
			if ([clippingTypes containsObject:type])
				[self addContentsOfClipping:clippingPath];
		}

		if ([self objectForType:kQSObjectPrimaryName])
			[self setName:[self objectForType:kQSObjectPrimaryName]];
		else {
			[self guessName];
		}
        if (![self name]) {
            if ([self objectForType:QSTextType]) {
                [self setName:[self objectForType:QSTextType]];
            } else {
                [self setName:NSLocalizedString(@"Unknown Clipboard Object", @"Name for an unknown clipboard object")];
            }
            [self setDetails:[NSString stringWithFormat:NSLocalizedString(@"Unknown type from %@",@"Details of unknown clipboard objects. Of the form 'Unknown type from Application'. E.g. 'Unknown type from Microsoft Word'"),sourceApp]];

        }
		[self loadIcon];
	}
	return self;
}
+ (id)objectWithClipping:(NSString *)clippingFile {
	return [[QSObject alloc] initWithClipping:clippingFile];
}
- (id)initWithClipping:(NSString *)clippingFile {
	NSPasteboard *pasteboard = [NSPasteboard pasteboardByFilteringClipping:clippingFile];
	if (self = [self initWithPasteboard:pasteboard]) {
		[self setLabel:[clippingFile lastPathComponent]];
	}
	[pasteboard releaseGlobally];
	return self;
}

- (void)guessName {
	if (itemForKey(NSFilenamesPboardType) ) {
		[self setPrimaryType:NSFilenamesPboardType];
		[self getNameFromFiles];
	} else {
        NSString *textString = itemForKey(NSStringPboardType);
        // some objects (images from the web) don't have a text string but have a URL
        if (!textString) {
            textString = itemForKey(NSURLPboardType);
        }
        textString = [textString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        
		static NSDictionary *namesAndKeys = nil;
        static NSArray *keys = nil;
        if (!keys) {
            // Use an array for the keys since the order is important
            keys = [NSArray arrayWithObjects:[@"'icns'" encodedPasteboardType],NSPostScriptPboardType,NSTIFFPboardType,NSColorPboardType,NSFileContentsPboardType,NSFontPboardType,NSPasteboardTypeRTF,NSHTMLPboardType,NSRulerPboardType,NSTabularTextPboardType,NSVCardPboardType,NSFilesPromisePboardType,NSPDFPboardType,QSTextType,nil];

        }
        if (!namesAndKeys) {
            namesAndKeys = [NSDictionary dictionaryWithObjectsAndKeys:
                                      NSLocalizedString(@"PDF Image", @"Name of PDF image "),                               NSPDFPboardType,
                                      NSLocalizedString(@"PNG Image", @"Name of a PNG image object"),
                                      NSPasteboardTypePNG,
                                      NSLocalizedString(@"RTF Text", @"Name of a RTF text object"),
                                      NSPasteboardTypeRTF,
                                      NSLocalizedString(@"Finder Icon", @"Name of icon file object"),                       [@"'icns'" encodedPasteboardType],
                                      NSLocalizedString(@"PostScript Image", @"Name of PostScript image object"),           NSPostScriptPboardType,
                                      NSLocalizedString(@"TIFF Image", @"Name of TIFF image object"),                       NSTIFFPboardType,
                                      NSLocalizedString(@"Color Data", @"Name of Color data object"),                       NSColorPboardType,
                                      NSLocalizedString(@"File Contents", @"Name of File contents object"),                 NSFileContentsPboardType,
                                      NSLocalizedString(@"Font Information", @"Name of Font information object"),           NSFontPboardType,
                                      NSLocalizedString(@"HTML Data", @"Name of HTML data object"),                         NSHTMLPboardType,
                                      NSLocalizedString(@"Paragraph Formatting", @"Name of Paragraph Formatting object"),   NSRulerPboardType,
                                      NSLocalizedString(@"Tabular Text", @"Name of Tabular text object"),                   NSTabularTextPboardType,
                                      NSLocalizedString(@"VCard Data", @"Name of VCard data object"),                       NSVCardPboardType,
                                      NSLocalizedString(@"Promised Files", @"Name of Promised files object"),               NSFilesPromisePboardType,
                                      nil];
        }

        for (NSString *key in keys) {
			if (itemForKey(key) ) {
                if ([key isEqualToString:QSTextType]) {
                    [self setDetails:nil];
                } else {
                    [self setDetails:[namesAndKeys objectForKey:key]];
                }
                [self setPrimaryType:key];
                [self setName:textString];
                break;
            }
		}
	}
}

- (BOOL)putOnPasteboardAsPlainTextOnly:(NSPasteboard *)pboard {
	NSArray *types = [NSArray arrayWithObject:NSStringPboardType];
	[pboard declareTypes:types owner:nil];
	NSString *string = [self stringValue];
	[pboard setString:string forType:NSStringPboardType];
	return YES;
}

// Declares the types that should be put on the pasteboard
- (BOOL)putOnPasteboard:(NSPasteboard *)pboard declareTypes:(NSArray *)types includeDataForTypes:(NSArray *)includeTypes {
	if (!types) {
		// get the different pboard types from the object's data dictionary -- they're all stored here
		types = [[[self dataDictionary] allKeys] mutableCopy];
		if ([types containsObject:QSProxyType])
			[(NSMutableArray *)types addObjectsFromArray:[[[self resolvedObject] dataDictionary] allKeys]];
	}
	else {
		NSMutableSet *typeSet = [NSMutableSet setWithArray:types];
		[typeSet intersectSet:[NSSet setWithArray:[[self dataDictionary] allKeys]]];
		types = [[typeSet allObjects] mutableCopy];
	}
	// If there are no types for the object, we need to set one (using stringValue)
	if (![types count]) {
		[(NSMutableArray *)types addObject:NSStringPboardType];
		[[self dataDictionary] setObject:[self stringValue] forKey:NSStringPboardType];
	}
	
	// define the types to be included on the pasteboard
	if (!includeTypes) {
		if ([types containsObject:NSFilenamesPboardType] || [types containsObject:QSFilePathType]) {
			includeTypes = [NSArray arrayWithObject:NSFilenamesPboardType];
		//			[pboard declareTypes:includeTypes owner:self];
        } else if ([types containsObject:NSURLPboardType]) {
			// for urls, define plain text, rtf and html
			includeTypes = [NSArray arrayWithObjects:NSURLPboardType,NSHTMLPboardType,NSRTFPboardType,NSStringPboardType,nil];
		} else if ([types containsObject:NSColorPboardType]) {
			includeTypes = [NSArray arrayWithObject:NSColorPboardType];
        }
	}
	// last case: no other useful types: return a basic string
	if (!includeTypes) {
		includeTypes = @[NSStringPboardType, QSTextType];
	}

	[pboard declareTypes:types owner:self];
	/*
	 // ***warning  ** Should add additional information for file items	 if ([paths count] == 1) {
	 [[self data] setObject:[[NSURL fileURLWithPath:[paths lastObject]]absoluteString] forKey:NSURLPboardType];
	 [[self data] setObject:[paths lastObject] forKey:NSStringPboardType];
	 }
	 */
	//  NSLog(@"declareTypes: %@", [types componentsJoinedByString:@", "]);
	
	// For URLs, create the RTF and HTML data to be stored in the clipboard
	if ([types containsObject:NSURLPboardType]) {
		// add the RTF and HTML types to the list of types
		types = [types arrayByAddingObjectsFromArray:[NSArray arrayWithObjects:NSHTMLPboardType,NSRTFPboardType,nil]];
		// Create the HTML and RTF data
		NSData *htmlData = [NSString dataForObject:self forType:NSHTMLPboardType];
		NSData *rtfData = [NSString dataForObject:self forType:NSRTFPboardType];
		// Add the HTML and RTF data to the object's data dictionary
		[[self dataDictionary] setObject:htmlData forKey:NSHTMLPboardType];	
		[[self dataDictionary] setObject:rtfData forKey:NSRTFPboardType];
	}
	
	for (NSString *thisType in includeTypes) {
		if ([types containsObject:thisType]) {
			// NSLog(@"includedata, %@", thisType);
			[self pasteboard:pboard provideDataForType:thisType];
		}
	}
	if ([self identifier]) {
		[pboard addTypes:[NSArray arrayWithObject:QSPasteboardObjectIdentifier] owner:self];
		writeObjectToPasteboard(pboard, QSPasteboardObjectIdentifier, [self stringValue]);
	}
	
	[pboard addTypes:[NSArray arrayWithObject:QSPasteboardObjectAddress] owner:self];
    QSLib.pasteboardObject = self;
	//  NSLog(@"types %@", [pboard types]);
	return YES;
}

- (void)pasteboard:(NSPasteboard *)sender provideDataForType:(NSString *)type {
	//if (VERBOSE) NSLog(@"Provide: %@", [type decodedPasteboardType]);
	if ([type isEqualToString:QSPasteboardObjectAddress]) {
		writeObjectToPasteboard(sender, type, [NSString stringWithFormat:@"copied object at %p", self]);
    } else {
		id theData = nil;
		id handler = [self handlerForType:type selector:@selector(dataForObject:pasteboardType:)];
		if (handler)
			theData = [handler dataForObject:self pasteboardType:type];
		if (!theData)
			theData = [self objectForType:type];
		if (theData) writeObjectToPasteboard(sender, type, theData);
	}
}

- (void)pasteboardChangedOwner:(NSPasteboard *)sender {
	//if (sender == [NSPasteboard generalPasteboard] && VERBOSE)
	//  NSLog(@"%@ Lost the Pasteboard: %@", self, sender);
}

- (NSData *)dataForType:(NSString *)dataType {
	id theData = [data objectForKey:dataType];
	if ([theData isKindOfClass:[NSData class]]) return theData;
	return nil;
}
@end
