#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Search options for find operations.
typedef NS_OPTIONS(NSUInteger, XEditorSearchFlags) {
    XEditorSearchCaseSensitive = 1 << 0,
    XEditorSearchRegex         = 1 << 1,
    XEditorSearchWholeWord     = 1 << 2,
    XEditorSearchWrap          = 1 << 3,
};

/// Outcome of a find/replace operation.
typedef NS_ENUM(NSInteger, XEditorFindStatus) {
    XEditorFindStatusOk = 0,
    XEditorFindStatusNotFound,
    XEditorFindStatusInvalidRegex,
    XEditorFindStatusBadRange,
};

/// One match. Offsets are UTF-8 byte positions in the document buffer.
@interface XEditorFindMatch : NSObject
@property (nonatomic, readonly) NSInteger start;
@property (nonatomic, readonly) NSInteger end;   // exclusive
@property (nonatomic, readonly) NSInteger line;  // 1-based
- (instancetype)initWithStart:(NSInteger)start end:(NSInteger)end line:(NSInteger)line;
@end

@interface XEditorFindResult : NSObject
@property (nonatomic, readonly) XEditorFindStatus status;
@property (nonatomic, readonly) BOOL wrapped;
@property (nonatomic, readonly, nullable) XEditorFindMatch *match;
- (instancetype)initWithStatus:(XEditorFindStatus)status
                       wrapped:(BOOL)wrapped
                         match:(nullable XEditorFindMatch *)match;
@end

@interface XEditorFindAllResult : NSObject
@property (nonatomic, readonly) XEditorFindStatus status;
@property (nonatomic, copy, readonly) NSArray<XEditorFindMatch *> *matches;
@property (nonatomic, readonly) BOOL truncated;
- (instancetype)initWithStatus:(XEditorFindStatus)status
                       matches:(NSArray<XEditorFindMatch *> *)matches
                     truncated:(BOOL)truncated;
@end

@interface XEditorCountResult : NSObject
@property (nonatomic, readonly) XEditorFindStatus status;
@property (nonatomic, readonly) NSInteger count;
- (instancetype)initWithStatus:(XEditorFindStatus)status count:(NSInteger)count;
@end

@interface XEditorReplaceResult : NSObject
@property (nonatomic, readonly) XEditorFindStatus status;
@property (nonatomic, readonly) NSInteger count;
@property (nonatomic, readonly) NSInteger replacedStart;
@property (nonatomic, readonly) NSInteger replacedEnd;
- (instancetype)initWithStatus:(XEditorFindStatus)status
                         count:(NSInteger)count
                 replacedStart:(NSInteger)replacedStart
                   replacedEnd:(NSInteger)replacedEnd;
@end

/// Objective-C++ bridge between SwiftUI and the Scintilla Cocoa editor.
@interface EditorBridge : NSObject

- (instancetype)initWithFrame:(NSRect)frame NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly) NSView *view;

/// Called on the main thread whenever the document's modified state changes.
@property (nonatomic, copy, nullable) void (^changeHandler)(BOOL isDirty);
/// Called on the main thread after text is inserted or deleted.
@property (nonatomic, copy, nullable) void (^contentChangeHandler)(void);

@property (nonatomic, readonly, getter=isDirty) BOOL dirty;

// MARK: - File I/O

- (void)loadFile:(NSString *)path;
- (void)loadFile:(NSString *)path encoding:(NSStringEncoding)encoding;
- (BOOL)writeFile:(NSString *)path;

/// The encoding detected (or manually set) for the current file.
@property (nonatomic, readonly) NSStringEncoding fileEncoding;

/// Reload the current file with a different encoding.
- (void)reloadWithEncoding:(NSStringEncoding)encoding;

// MARK: - Text

- (NSString *)text;
- (void)setText:(NSString *)text;

// MARK: - Lexer

/// Lexilla lexer name, e.g. "cpp", "python", "markdown", "null".
- (void)setLexerName:(NSString *)name;
/// Keyword lists for the current lexer, in SCI_SETKEYWORDS index order.
/// Pass an empty string for unused slots.
- (void)setKeywordSets:(NSArray<NSString *> *)sets;
/// Re-run the current lexer over the whole document (needed when switching
/// languages after the text has already been styled).
- (void)restyleAll;

// MARK: - Find & Replace

/// Find the next occurrence. Returns byte position or -1 if not found.
- (NSInteger)findNext:(NSString *)text flags:(XEditorSearchFlags)flags;
/// Find the previous occurrence. Returns byte position or -1 if not found.
- (NSInteger)findPrevious:(NSString *)text flags:(XEditorSearchFlags)flags;
/// Count all matches in the document.
- (NSInteger)matchCount:(NSString *)text flags:(XEditorSearchFlags)flags;
/// Replace the current selection (assumed to be a match).
- (BOOL)replaceCurrent:(NSString *)replacement regex:(BOOL)regex;
/// Replace all occurrences. Returns the number of replacements made.
- (NSInteger)replaceAll:(NSString *)text
                   with:(NSString *)replacement
                  flags:(XEditorSearchFlags)flags;
/// Returns the currently selected text.
- (NSString *)selectedText;

// MARK: - Byte-exact find & replace

/// Find `needle` starting at `startPosition`. When `forward` is NO the search
/// runs backwards from `startPosition` to the start of the document. `wrap`
/// continues from the opposite end of the document when nothing is found.
/// Byte offsets, so patterns containing NUL (Extended mode) work.
- (XEditorFindResult *)findBytes:(NSData *)needle
                           flags:(XEditorSearchFlags)flags
                   startPosition:(NSInteger)startPosition
                         forward:(BOOL)forward
                            wrap:(BOOL)wrap
    NS_SWIFT_NAME(findBytes(_:flags:startPosition:forward:wrap:));

/// All matches in [start, end). `maxCount` <= 0 means unlimited.
- (XEditorFindAllResult *)findAllBytes:(NSData *)needle
                                 flags:(XEditorSearchFlags)flags
                               inStart:(NSInteger)start
                                 inEnd:(NSInteger)end
                              maxCount:(NSInteger)maxCount
    NS_SWIFT_NAME(findAllBytes(_:flags:inStart:inEnd:maxCount:));

- (XEditorCountResult *)countBytes:(NSData *)needle
                             flags:(XEditorSearchFlags)flags
                           inStart:(NSInteger)start
                             inEnd:(NSInteger)end
    NS_SWIFT_NAME(countBytes(_:flags:inStart:inEnd:));

/// Replace the selection when it matches `needle`; otherwise nothing changes.
/// The inserted text ends up selected. Mirrors notepad--'s Replace button.
- (XEditorReplaceResult *)replaceCurrentBytes:(NSData *)needle
                                  replacement:(NSData *)replacement
                                        flags:(XEditorSearchFlags)flags
    NS_SWIFT_NAME(replaceCurrentBytes(_:replacement:flags:));

/// Replace every match in [start, end) as a single undo action.
- (XEditorReplaceResult *)replaceAllBytes:(NSData *)needle
                              replacement:(NSData *)replacement
                                    flags:(XEditorSearchFlags)flags
                                  inStart:(NSInteger)start
                                    inEnd:(NSInteger)end
    NS_SWIFT_NAME(replaceAllBytes(_:replacement:flags:inStart:inEnd:));

/// Replace an exact target range without searching first (internal for the
/// regex path: refreshes back-reference positions). Returns inserted length.
- (NSInteger)replaceBytes:(NSData *)replacement
                  inStart:(NSInteger)start
                    inEnd:(NSInteger)end
                    regex:(BOOL)regex
    NS_SWIFT_NAME(replaceBytes(_:inStart:inEnd:regex:));

// MARK: - Selection / offsets

@property (nonatomic, readonly) NSInteger selectionStart; // byte offset
@property (nonatomic, readonly) NSInteger selectionEnd;   // byte offset
@property (nonatomic, readonly) NSInteger documentLength;

- (NSInteger)positionAfterPosition:(NSInteger)position NS_SWIFT_NAME(positionAfterPosition(_:));
- (NSInteger)positionBeforePosition:(NSInteger)position NS_SWIFT_NAME(positionBeforePosition(_:));
- (void)selectRangeStart:(NSInteger)start end:(NSInteger)end NS_SWIFT_NAME(selectRange(start:end:));
/// `line` is 1-based; `rangeInLine` is a UTF-16 range within that line.
- (void)selectLine:(NSInteger)line rangeInLine:(NSRange)rangeInLine NS_SWIFT_NAME(selectLine(_:rangeInLine:));
/// Text of a 1-based line, without its line terminator.
- (NSString *)lineText:(NSInteger)line NS_SWIFT_NAME(lineText(_:));
/// UTF-8 byte offset of the first character of a 1-based line.
- (NSInteger)lineStartPosition:(NSInteger)line NS_SWIFT_NAME(lineStartPosition(_:));

// MARK: - Marks

/// Fill indicator `indicator` over every match. Zero-length matches are
/// skipped (an empty range draws nothing).
- (XEditorCountResult *)markAllBytes:(NSData *)needle
                               flags:(XEditorSearchFlags)flags
                           indicator:(NSInteger)indicator
                            maxCount:(NSInteger)maxCount
    NS_SWIFT_NAME(markAllBytes(_:flags:indicator:maxCount:));
- (void)clearIndicatorRange:(NSInteger)indicator NS_SWIFT_NAME(clearIndicatorRange(_:));
/// Clears the five mark indicators (21..25).
- (void)clearAllMarkIndicators;
/// Swatch colour for mark index 0..4, matching the indicator palette the
/// editor uses for the current theme.
+ (NSColor *)markColorForIndex:(NSInteger)index dark:(BOOL)dark
    NS_SWIFT_NAME(markColor(index:dark:));
- (void)addBookmarkAtLine:(NSInteger)line NS_SWIFT_NAME(addBookmark(atLine:)); // idempotent

// MARK: - Navigation

/// Jump to the given 1-based line number.
- (void)goToLine:(NSInteger)line NS_SWIFT_NAME(goToLine(_:));
/// Returns the current 1-based line number.
- (NSInteger)currentLine;
/// Returns the current 1-based column number.
- (NSInteger)currentColumn;

// MARK: - Bookmarks

- (void)toggleBookmarkAtCurrentLine;
- (void)nextBookmark;
- (void)previousBookmark;
- (void)clearAllBookmarks;

// MARK: - Code Folding

- (void)foldAll;
- (void)unfoldAll;
- (void)toggleFoldCurrent;

// MARK: - Line Operations & Text Transformation

- (void)duplicateLine;
- (void)deleteLine;
- (void)moveLineUp;
- (void)moveLineDown;
- (void)joinLines;
- (void)toUpperCase;
- (void)toLowerCase;
- (void)toggleCommentWithPrefix:(NSString *)prefix;
- (void)trimTrailingWhitespace;
- (void)sortSelectedLinesAscending:(BOOL)ascending;

// MARK: - Info

- (NSInteger)lineCount;
- (NSInteger)currentPosition;

// MARK: - Appearance

- (void)applyThemeDark:(BOOL)dark;
- (void)setEditorFont:(NSString *)fontName size:(CGFloat)fontSize;
- (void)setTabWidth:(NSInteger)width;
- (void)setUseTabs:(BOOL)useTabs;
- (void)setWordWrap:(BOOL)wrap;
- (void)setShowWhitespace:(BOOL)show;
- (void)setShowIndentGuides:(BOOL)show;

/// Recalculate line number margin width based on current line count.
- (void)updateLineNumberMarginWidth;

@end

NS_ASSUME_NONNULL_END
