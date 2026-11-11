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
