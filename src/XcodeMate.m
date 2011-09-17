//
//  XcodeMate.m
//  XcodeMate
//
//  Copyright 2009-2010 Ciarán Walsh, Adam Strzelecki. All rights reserved.
//

#import "XcodeMate.h"
#import "JRSwizzle.h"

@interface NSObject (DevToolsInterfaceAdditions)
// XCTextStorageAdditions
- (id)language;

// XCSourceModel
- (id)sourceModel;
- (BOOL)isInStringConstantAtLocation:(NSUInteger)index;

// XCSourceCodeTextView
- (BOOL)isInlineCompleting;
- (id)codeAssistant;

// DVTSourceCodeLanguage
- (id)identifier;
@end

static NSSet *XcodeMateLanguages;
static NSString *OpeningsClosings = @"\"\"''()[]";

@implementation NSTextView (XcodeMate)
- (void)XcodeMate_keyDown:(NSEvent*)event
{
	BOOL didInsert = NO;
	if([event.charactersIgnoringModifiers isEqualToString:@"D"] &&
	   ([event modifierFlags] & NSControlKeyMask)) {
		didInsert = [self XcodeMate_duplicateSelectionInTextView:self];
	} else {
		NSRange range = [OpeningsClosings rangeOfString:event.characters];
		if(range.length == 1 && range.location % 2 == 0) {
			NSString *language = [[self textStorage] language];
			if(![language isKindOfClass:[NSString class]]) {
				language = [language identifier];
			}
			if([XcodeMateLanguages containsObject:language]) {
				NSRange selectedRange = [[[self selectedRanges] lastObject] rangeValue];
				if(![[[self textStorage] sourceModel] isInStringConstantAtLocation:selectedRange.location]) {
					range.location ++;
					NSString *closing = [OpeningsClosings substringWithRange:range];
					didInsert = [self XcodeMate_insertForTextView:self opening:event.characters closing:closing];
				}
			}
		}
	}

	if(!didInsert)
		[self XcodeMate_keyDown:event];
}

- (void)XcodeMate_deleteBackward:(NSEvent*)event
{
	NSTextView *textView = self;
	NSRange selectedRange = [[[textView selectedRanges] lastObject] rangeValue];
	if(selectedRange.length == 0) {
		NSRange checkRange = NSMakeRange(selectedRange.location - 1, 2);
		@try {
			NSString *substring = [[[textView textStorage] string] substringWithRange:checkRange];
			NSRange range = [OpeningsClosings rangeOfString:substring];
			if(range.length == 2 && range.location % 2 == 0) {
				NSString *language = [[self textStorage] language];
				if(![language isKindOfClass:[NSString class]]) {
					language = [language identifier];
				}
				if([XcodeMateLanguages containsObject:language]) {
					[textView moveForward:event];
					[textView XcodeMate_deleteBackward:event];
				}
			}
		} @catch(NSException *e) {
			if(![e.name isEqualToString:NSRangeException]) {
				[e raise];
			}
		}
	}
	[self XcodeMate_deleteBackward:event];
}

static NSUInteger TextViewLineIndex (NSTextView *textView)
{
	NSRange selectedRange = [[[textView selectedRanges] lastObject] rangeValue];
	NSUInteger res        = selectedRange.location;
	NSString *substring   = [[[textView textStorage] string] substringToIndex:selectedRange.location];
	NSUInteger newline    = [substring rangeOfString:@"\n" options:NSBackwardsSearch].location;
	if(newline != NSNotFound)
		res -= newline + 1;
	return res;
}

- (BOOL)XcodeMate_insertForTextView:(NSTextView *)textView opening:(NSString *)opening closing:(NSString *)closing
{
	NSRange selectedRange = [[[textView selectedRanges] lastObject] rangeValue];
	
	if(selectedRange.length > 0)
	{
		NSString *selectedText = [textView.textStorage.string substringWithRange:selectedRange];
		// NOTE: If we are in the placeholder, replace it
		if([selectedText hasPrefix:@"<#"] &&
		   [selectedText hasSuffix:@"#>"]) {
			[textView insertText:opening];
			[textView insertText:closing];
			[textView moveBackward:self];
		} else {
			[textView insertText:opening];
			[textView insertText:selectedText];
			[textView insertText:closing];
		}
	} else {
		[textView insertText:opening];
		[textView insertText:closing];
		[textView moveBackward:self];
	}
	
	return YES;
}

- (BOOL)XcodeMate_duplicateSelectionInTextView:(NSTextView *)textView
{
	NSRange selectedRange = [[[textView selectedRanges] lastObject] rangeValue];
	if(selectedRange.length > 0) {
		NSString *selection = [textView.textStorage.string substringWithRange:selectedRange];
		[textView.undoManager beginUndoGrouping];
		[[textView.undoManager prepareWithInvocationTarget:textView] replaceCharactersInRange:selectedRange withString:@""];
		[textView.undoManager endUndoGrouping];
		[textView replaceCharactersInRange:NSMakeRange(selectedRange.location, 0) withString:selection];
	} else {
		NSUInteger start, end, contentsEnd;
		[[[textView textStorage] string] getParagraphStart:&start end:&end contentsEnd:&contentsEnd forRange:selectedRange];
		NSRange paragraphRange = NSMakeRange(start, end - start);
		NSString *paragraph = [[[textView textStorage] string] substringWithRange:paragraphRange];
		[textView.undoManager beginUndoGrouping];
		[[textView.undoManager prepareWithInvocationTarget:textView] replaceCharactersInRange:paragraphRange withString:@""];
		[textView.undoManager endUndoGrouping];
		[textView replaceCharactersInRange:NSMakeRange(start, 0) withString:paragraph];
	}
	
	return YES;
}
@end

@implementation XcodeMate

+ (void)pluginDidLoad:(NSBundle *)bundle
{
	// Xcode 4 support
	if(![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.Xcode"]) {
		if(![[[NSBundle mainBundle] bundleIdentifier] isEqualToString:@"com.apple.dt.Xcode"]) {
			NSLog(@"XcodeMate unknown bundle identifier: %@", [[NSBundle mainBundle] bundleIdentifier]);
			return;
		}
		NSError *error = nil;
		if(![NSClassFromString(@"DVTSourceTextView") jr_swizzleMethod:@selector(keyDown:) withMethod:@selector(XcodeMate_keyDown:) error:&error]) {
			NSLog(@"XcodeMate failed to swizzle `-[DVTSourceTextView keyDown:]', %@", [error localizedDescription]);
		}
		error = nil;
		if(![NSClassFromString(@"DVTSourceTextView") jr_swizzleMethod:@selector(deleteBackward:) withMethod:@selector(XcodeMate_deleteBackward:) error:&error]) {
			NSLog(@"XcodeMate failed to swizzle `-[DVTSourceTextView deleteBackward:]', %@", [error localizedDescription]);
		}
	} else { // Xcode 3.x support
		NSError *error = nil;
		if(![NSClassFromString(@"XCSourceCodeTextView") jr_swizzleMethod:@selector(keyDown:) withMethod:@selector(XcodeMate_keyDown:) error:&error]) {
			NSLog(@"XcodeMate failed to swizzle `-[XCSourceCodeTextView keyDown:]', %@", [error localizedDescription]);
		}
		error = nil;
		if(![NSClassFromString(@"XCSourceCodeTextView") jr_swizzleMethod:@selector(deleteBackward:) withMethod:@selector(XcodeMate_deleteBackward:) error:&error]) {
			NSLog(@"XcodeMate failed to swizzle `-[XCSourceCodeTextView deleteBackward:]', %@", [error localizedDescription]);
		}
	}

	XcodeMateLanguages = [[NSSet alloc] initWithObjects:
						  @"xcode.lang.c", // Xcode 3
						  @"xcode.lang.cpp",
						  @"xcode.lang.objcpp",
						  @"xcode.lang.objc",
						  @"xcode.lang.objj",
						  @"Xcode.SourceCodeLanguage.C", // Xcode 4
						  @"Xcode.SourceCodeLanguage.C++",
						  @"Xcode.SourceCodeLanguage.Objective-C",
						  @"Xcode.SourceCodeLanguage.Objective-C++",
						  @"Xcode.SourceCodeLanguage.Objective-J",
						  nil];

	NSLog(@"XcodeMate %@ loaded.", [[NSBundle mainBundle] objectForInfoDictionaryKey:(NSString *)kCFBundleVersionKey]);
}

@end
