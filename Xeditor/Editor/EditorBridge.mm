#import "EditorBridge.h"

#import "ScintillaView.h"

#include "Scintilla.h"
#include "SciLexer.h"
#include "ILexer.h"
#include "Lexilla.h"

#include <ctype.h>

// Lexilla exports this C entry point; when statically linked we declare it here.
extern "C" Scintilla::ILexer5 *CreateLexer(const char *name);

// Indicator used to mark every occurrence of the current selection.
// Scintilla reserves 8 (container lexer), 32-35 (IME) and 36-43 (undo history),
// so 20 is safely outside every reserved range.
static const int INDICATOR_OCCURRENCE = 20;

static int ColorRefFromNSColor(NSColor *color) {
    NSColor *rgb = [color colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
    if (!rgb) {
        return 0;
    }
    const int r = (int)lround(rgb.redComponent * 255.0);
    const int g = (int)lround(rgb.greenComponent * 255.0);
    const int b = (int)lround(rgb.blueComponent * 255.0);
    return (b << 16) | (g << 8) | r;
}

// ---------------------------------------------------------------------------
// Encoding detection heuristics
// ---------------------------------------------------------------------------

static BOOL dataIsValidUTF8(const uint8_t *data, NSUInteger length) {
    NSUInteger i = 0;
    BOOL hasMultibyte = NO;
    while (i < length) {
        if (data[i] < 0x80) { i++; continue; }
        int trailing = 0;
        if      ((data[i] & 0xE0) == 0xC0) trailing = 1;
        else if ((data[i] & 0xF0) == 0xE0) trailing = 2;
        else if ((data[i] & 0xF8) == 0xF0) trailing = 3;
        else return NO;
        if (i + trailing >= length) return NO;
        for (int j = 1; j <= trailing; j++) {
            if ((data[i + j] & 0xC0) != 0x80) return NO;
        }
        hasMultibyte = YES;
        i += trailing + 1;
    }
    (void)hasMultibyte;
    return YES;
}

static NSStringEncoding detectEncoding(NSData *data) {
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    const NSUInteger len = data.length;

    // BOM detection
    if (len >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
        return NSUTF8StringEncoding;
    }
    if (len >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
        return NSUTF16LittleEndianStringEncoding;
    }
    if (len >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
        return NSUTF16BigEndianStringEncoding;
    }

    // If valid UTF-8 with only ASCII it's also valid Latin1/GBK — call it UTF-8.
    if (dataIsValidUTF8(bytes, len)) {
        return NSUTF8StringEncoding;
    }

    // Try GB18030 (superset of GBK / GB2312)
    NSStringEncoding gb18030 =
        CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    if ([[NSString alloc] initWithData:data encoding:gb18030]) {
        return gb18030;
    }

    // Fallback: ISO Latin 1
    return NSISOLatin1StringEncoding;
}

// ---------------------------------------------------------------------------

@interface EditorBridge () <ScintillaNotificationProtocol>
@property (nonatomic, strong) ScintillaView *sci;
@property (nonatomic, assign) BOOL lastKnownDirty;
// Deliberately NOT named `lexerName`; avoids collision with the public setter.
@property (nonatomic, copy) NSString *currentLexer;
@property (nonatomic, assign) BOOL darkTheme;
@property (nonatomic, copy, nullable) NSString *filePath;
@property (nonatomic, readwrite) NSStringEncoding fileEncoding;
- (void)updateDirtyState;
@end

@implementation EditorBridge

// ---------------------------------------------------------------------------
#pragma mark - Lifecycle
// ---------------------------------------------------------------------------

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super init];
    if (self) {
        _sci = [[ScintillaView alloc] initWithFrame:frame];
        _sci.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _currentLexer = @"null";
        _fileEncoding = NSUTF8StringEncoding;
        [self configureEditor];
    }
    return self;
}

- (void)dealloc {
    // ScintillaView holds its delegate unretained; SwiftUI may keep the view
    // alive briefly after the bridge goes away, so break the back-pointer.
    if (_sci.delegate == self) {
        _sci.delegate = nil;
    }
}

- (NSView *)view {
    return self.sci;
}

// ---------------------------------------------------------------------------
#pragma mark - Initial Configuration
// ---------------------------------------------------------------------------

- (void)configureEditor {
    ScintillaView *sci = self.sci;
    sci.delegate = self;

    [sci message:SCI_SETCODEPAGE wParam:SC_CP_UTF8 lParam:0];

    // Line-number margin (index 0)
    [sci message:SCI_SETMARGINTYPEN  wParam:0 lParam:SC_MARGIN_NUMBER];
    [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:48];

    // Bookmark margin (index 1)
    static const int MARKER_BOOKMARK = 0;
    [sci message:SCI_SETMARGINTYPEN  wParam:1 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN  wParam:1 lParam:(1 << MARKER_BOOKMARK)];
    [sci message:SCI_SETMARGINWIDTHN wParam:1 lParam:16];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:1 lParam:1];
    [sci message:SCI_MARKERDEFINE wParam:MARKER_BOOKMARK lParam:SC_MARK_ROUNDRECT];
    [sci message:SCI_MARKERSETBACK wParam:MARKER_BOOKMARK lParam:ColorRefFromNSColor([NSColor systemBlueColor])];

    // Code folding margin (index 2)
    [sci message:SCI_SETMARGINTYPEN  wParam:2 lParam:SC_MARGIN_SYMBOL];
    [sci message:SCI_SETMARGINMASKN  wParam:2 lParam:SC_MASK_FOLDERS];
    [sci message:SCI_SETMARGINWIDTHN wParam:2 lParam:14];
    [sci message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN    lParam:SC_MARK_BOXMINUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER        lParam:SC_MARK_BOXPLUS];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB     lParam:SC_MARK_VLINE];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL    lParam:SC_MARK_LCORNER];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND     lParam:SC_MARK_BOXPLUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
    [sci message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];
    [sci message:SCI_SETFOLDFLAGS wParam:SC_FOLDFLAG_LINEAFTER_CONTRACTED lParam:0];
    [sci message:SCI_SETAUTOMATICFOLD wParam:SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE lParam:0];

    // Tabs & indentation
    [sci message:SCI_SETTABWIDTH wParam:4 lParam:0];
    [sci message:SCI_SETUSETABS  wParam:0 lParam:0];

    // Word wrap off by default
    [sci message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];

    // Caret line highlight
    [sci message:SCI_SETCARETLINEVISIBLE       wParam:1 lParam:0];
    [sci message:SCI_SETCARETLINEVISIBLEALWAYS  wParam:1 lParam:0];

    // "Highlight all occurrences of the selection": a translucent rounded box
    // drawn under the text so syntax colours stay readable. The colour itself
    // is set per theme in applyThemeDark:.
    [sci message:SCI_INDICSETSTYLE       wParam:INDICATOR_OCCURRENCE lParam:INDIC_ROUNDBOX];
    [sci message:SCI_INDICSETUNDER       wParam:INDICATOR_OCCURRENCE lParam:1];
    [sci message:SCI_INDICSETALPHA       wParam:INDICATOR_OCCURRENCE lParam:60];
    [sci message:SCI_INDICSETOUTLINEALPHA wParam:INDICATOR_OCCURRENCE lParam:100];

    // Default font. "SF Mono" ships with Terminal/Xcode but is not installed as
    // a regular system font, so it silently resolved to Helvetica. Menlo is
    // always available and keeps the editor monospaced.
    [sci setFontName:@"Menlo" size:13 bold:NO italic:NO];

    // Detect system appearance
    BOOL dark = NO;
    if (NSApp) {
        NSString *match = [NSApp.effectiveAppearance
            bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua,
                                                NSAppearanceNameDarkAqua]];
        dark = [match isEqualToString:NSAppearanceNameDarkAqua];
    }
    [self applyThemeDark:dark];
}

// ---------------------------------------------------------------------------
#pragma mark - File I/O
// ---------------------------------------------------------------------------

- (void)loadFile:(NSString *)path {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data) {
        [self.sci setString:@""];
        return;
    }
    NSStringEncoding enc = detectEncoding(data);
    [self loadData:data path:path encoding:enc];
}

- (void)loadFile:(NSString *)path encoding:(NSStringEncoding)encoding {
    NSData *data = [NSData dataWithContentsOfFile:path options:0 error:nil];
    if (!data) {
        [self.sci setString:@""];
        return;
    }
    [self loadData:data path:path encoding:encoding];
}

- (void)loadData:(NSData *)data path:(NSString *)path encoding:(NSStringEncoding)encoding {
    self.filePath = path;
    self.fileEncoding = encoding;

    NSString *text = [[NSString alloc] initWithData:data encoding:encoding];
    if (!text) {
        text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
        self.fileEncoding = NSISOLatin1StringEncoding;
    }

    [self.sci setString:text ?: @""];
    [self.sci message:SCI_EMPTYUNDOBUFFER wParam:0 lParam:0];
    [self.sci message:SCI_SETSAVEPOINT    wParam:0 lParam:0];
    [self.sci message:SCI_GOTOPOS         wParam:0 lParam:0];
    self.lastKnownDirty = self.isDirty;
    [self updateLineNumberMarginWidth];
}

- (void)reloadWithEncoding:(NSStringEncoding)encoding {
    if (!self.filePath) return;
    [self loadFile:self.filePath encoding:encoding];
}

- (BOOL)writeFile:(NSString *)path {
    NSError *error = nil;
    BOOL ok = [[self.sci string] writeToFile:path
                                  atomically:YES
                                    encoding:NSUTF8StringEncoding
                                       error:&error];
    if (ok) {
        [self.sci message:SCI_SETSAVEPOINT wParam:0 lParam:0];
        self.fileEncoding = NSUTF8StringEncoding;
    }
    return ok;
}

// ---------------------------------------------------------------------------
#pragma mark - Text
// ---------------------------------------------------------------------------

- (NSString *)text {
    return [self.sci string] ?: @"";
}

- (void)setText:(NSString *)text {
    [self.sci setString:text ?: @""];
}

// ---------------------------------------------------------------------------
#pragma mark - Lexer
// ---------------------------------------------------------------------------

- (void)setLexerName:(NSString *)name {
    NSString *resolved = name.length > 0 ? name : @"null";
    Scintilla::ILexer5 *lexer = CreateLexer(resolved.UTF8String);
    if (!lexer) {
        return;
    }

    [self.sci setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
    _currentLexer = resolved;
    [self.sci setLexerProperty:@"fold" value:@"1"];
    [self.sci setLexerProperty:@"fold.compact" value:@"0"];
    [self.sci setLexerProperty:@"fold.comment" value:@"1"];
    [self.sci setLexerProperty:@"fold.preprocessor" value:@"1"];
    if ([resolved isEqualToString:@"cpp"]) {
        // The cpp lexer is also the fallback for JavaScript/TypeScript and Go.
        [self.sci setLexerProperty:@"lexer.cpp.allow.dollars" value:@"1"];
        [self.sci setLexerProperty:@"lexer.cpp.backquoted.strings" value:@"2"];
    }
    if ([resolved isEqualToString:@"markdown"]) {
        // Style the whole heading line, not just the leading '#' markers.
        [self.sci setLexerProperty:@"lexer.markdown.header.eolfill" value:@"1"];
    }
    // Reapply the whole theme: SCI_STYLECLEARALL removes style colours left
    // over from the previous lexer before the per-lexer palette is applied.
    [self applyThemeDark:self.darkTheme];
    // No eager SCI_COLOURISE here: after a fresh load Scintilla styles the
    // visible range on paint, which keeps opening large files interactive.
}

- (void)setKeywordSets:(NSArray<NSString *> *)sets {
    for (NSUInteger i = 0; i < sets.count; i++) {
        NSString *words = sets[i];
        if (words.length == 0) {
            continue;
        }
        [self.sci setReferenceProperty:SCI_SETKEYWORDS
                             parameter:(long)i
                                 value:words.UTF8String];
    }
}

- (void)restyleAll {
    [self.sci message:SCI_COLOURISE wParam:0 lParam:-1];
}

// ---------------------------------------------------------------------------
#pragma mark - Find & Replace
// ---------------------------------------------------------------------------

- (int)sciFlagsFrom:(XEditorSearchFlags)flags {
    int sf = 0;
    if (flags & XEditorSearchCaseSensitive) sf |= SCFIND_MATCHCASE;
    if (flags & XEditorSearchRegex)         sf |= SCFIND_REGEXP | SCFIND_POSIX;
    if (flags & XEditorSearchWholeWord)     sf |= SCFIND_WHOLEWORD;
    return sf;
}

- (NSInteger)findNext:(NSString *)text flags:(XEditorSearchFlags)flags {
    if (text.length == 0) return -1;
    ScintillaView *sci = self.sci;
    const char *s = text.UTF8String;
    const int sf = [self sciFlagsFrom:flags];

    sptr_t selEnd = [sci message:SCI_GETSELECTIONEND wParam:0 lParam:0];
    sptr_t docLen = [sci message:SCI_GETLENGTH        wParam:0 lParam:0];

    [sci message:SCI_SETTARGETSTART  wParam:selEnd lParam:0];
    [sci message:SCI_SETTARGETEND    wParam:docLen lParam:0];
    [sci message:SCI_SETSEARCHFLAGS  wParam:sf     lParam:0];

    sptr_t pos = [sci message:SCI_SEARCHINTARGET wParam:strlen(s) lParam:(sptr_t)s];

    if (pos < 0 && (flags & XEditorSearchWrap)) {
        [sci message:SCI_SETTARGETSTART wParam:0      lParam:0];
        [sci message:SCI_SETTARGETEND   wParam:selEnd lParam:0];
        pos = [sci message:SCI_SEARCHINTARGET wParam:strlen(s) lParam:(sptr_t)s];
    }

    if (pos >= 0) {
        sptr_t end = [sci message:SCI_GETTARGETEND wParam:0 lParam:0];
        [sci message:SCI_SETSEL      wParam:pos lParam:end];
        [sci message:SCI_SCROLLCARET wParam:0   lParam:0];
    }
    return (NSInteger)pos;
}

- (NSInteger)findPrevious:(NSString *)text flags:(XEditorSearchFlags)flags {
    if (text.length == 0) return -1;
    ScintillaView *sci = self.sci;
    const char *s = text.UTF8String;
    const int sf = [self sciFlagsFrom:flags];

    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];

    // Search backwards: target start > target end signals reverse search.
    [sci message:SCI_SETTARGETSTART  wParam:selStart lParam:0];
    [sci message:SCI_SETTARGETEND    wParam:0        lParam:0];
    [sci message:SCI_SETSEARCHFLAGS  wParam:sf       lParam:0];

    sptr_t pos = [sci message:SCI_SEARCHINTARGET wParam:strlen(s) lParam:(sptr_t)s];

    if (pos < 0 && (flags & XEditorSearchWrap)) {
        sptr_t docLen = [sci message:SCI_GETLENGTH wParam:0 lParam:0];
        [sci message:SCI_SETTARGETSTART wParam:docLen   lParam:0];
        [sci message:SCI_SETTARGETEND   wParam:selStart lParam:0];
        pos = [sci message:SCI_SEARCHINTARGET wParam:strlen(s) lParam:(sptr_t)s];
    }

    if (pos >= 0) {
        sptr_t end = [sci message:SCI_GETTARGETEND wParam:0 lParam:0];
        [sci message:SCI_SETSEL      wParam:pos lParam:end];
        [sci message:SCI_SCROLLCARET wParam:0   lParam:0];
    }
    return (NSInteger)pos;
}

- (NSInteger)matchCount:(NSString *)text flags:(XEditorSearchFlags)flags {
    if (text.length == 0) return 0;
    ScintillaView *sci = self.sci;
    const char *s = text.UTF8String;
    const int sf = [self sciFlagsFrom:flags];
    sptr_t docLen = [sci message:SCI_GETLENGTH wParam:0 lParam:0];

    NSInteger count = 0;
    sptr_t searchStart = 0;

    while (searchStart < docLen) {
        [sci message:SCI_SETTARGETSTART wParam:searchStart lParam:0];
        [sci message:SCI_SETTARGETEND   wParam:docLen      lParam:0];
        [sci message:SCI_SETSEARCHFLAGS wParam:sf          lParam:0];

        sptr_t pos = [sci message:SCI_SEARCHINTARGET wParam:strlen(s) lParam:(sptr_t)s];
        if (pos < 0) break;

        count++;
        sptr_t targetEnd = [sci message:SCI_GETTARGETEND wParam:0 lParam:0];
        searchStart = targetEnd > searchStart ? targetEnd : searchStart + 1;
    }
    return count;
}

- (BOOL)replaceCurrent:(NSString *)replacement regex:(BOOL)regex {
    ScintillaView *sci = self.sci;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND   wParam:0 lParam:0];
    if (selStart == selEnd) return NO;

    [sci message:SCI_SETTARGETSTART wParam:selStart lParam:0];
    [sci message:SCI_SETTARGETEND   wParam:selEnd   lParam:0];

    const char *r = replacement.UTF8String;
    if (regex) {
        [sci message:SCI_REPLACETARGETRE wParam:-1 lParam:(sptr_t)r];
    } else {
        [sci message:SCI_REPLACETARGET   wParam:-1 lParam:(sptr_t)r];
    }
    return YES;
}

- (NSInteger)replaceAll:(NSString *)text
                   with:(NSString *)replacement
                  flags:(XEditorSearchFlags)flags {
    if (text.length == 0) return 0;
    ScintillaView *sci = self.sci;
    const char *s = text.UTF8String;
    const char *r = replacement.UTF8String;
    const int sf = [self sciFlagsFrom:flags];
    const BOOL regex = (flags & XEditorSearchRegex) != 0;

    [sci message:SCI_BEGINUNDOACTION wParam:0 lParam:0];

    NSInteger count = 0;
    sptr_t searchStart = 0;

    while (YES) {
        sptr_t docLen = [sci message:SCI_GETLENGTH wParam:0 lParam:0];
        [sci message:SCI_SETTARGETSTART wParam:searchStart lParam:0];
        [sci message:SCI_SETTARGETEND   wParam:docLen      lParam:0];
        [sci message:SCI_SETSEARCHFLAGS wParam:sf          lParam:0];

        sptr_t pos = [sci message:SCI_SEARCHINTARGET wParam:strlen(s) lParam:(sptr_t)s];
        if (pos < 0) break;

        sptr_t repLen;
        if (regex) {
            repLen = [sci message:SCI_REPLACETARGETRE wParam:-1 lParam:(sptr_t)r];
        } else {
            repLen = [sci message:SCI_REPLACETARGET   wParam:-1 lParam:(sptr_t)r];
        }
        searchStart = pos + (repLen > 0 ? repLen : 1);
        count++;
    }

    [sci message:SCI_ENDUNDOACTION wParam:0 lParam:0];
    return count;
}

- (NSString *)selectedText {
    ScintillaView *sci = self.sci;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND   wParam:0 lParam:0];
    if (selStart == selEnd) return @"";

    sptr_t len = selEnd - selStart + 1;
    char *buf = (char *)calloc((size_t)len + 1, 1);
    [sci message:SCI_GETSELTEXT wParam:0 lParam:(sptr_t)buf];
    NSString *result = [NSString stringWithUTF8String:buf] ?: @"";
    free(buf);
    return result;
}

// ---------------------------------------------------------------------------
#pragma mark - Navigation
// ---------------------------------------------------------------------------

- (void)goToLine:(NSInteger)line {
    sptr_t idx = (sptr_t)(line - 1);       // 1-based → 0-based
    if (idx < 0) idx = 0;
    [self.sci message:SCI_GOTOLINE   wParam:idx lParam:0];
    [self.sci message:SCI_SCROLLCARET wParam:0  lParam:0];
}

- (NSInteger)currentLine {
    sptr_t pos = [self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0];
    return (NSInteger)[self.sci message:SCI_LINEFROMPOSITION wParam:pos lParam:0] + 1;
}

- (NSInteger)currentColumn {
    sptr_t pos  = [self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0];
    sptr_t col  = [self.sci message:SCI_GETCOLUMN     wParam:pos lParam:0];
    return (NSInteger)(col + 1);
}

- (NSInteger)currentPosition {
    return (NSInteger)[self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0];
}

// ---------------------------------------------------------------------------
#pragma mark - Bookmarks
// ---------------------------------------------------------------------------

- (void)toggleBookmarkAtCurrentLine {
    sptr_t line = [self.sci message:SCI_LINEFROMPOSITION wParam:[self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0] lParam:0];
    sptr_t state = [self.sci message:SCI_MARKERGET wParam:line lParam:0];
    if (state & (1 << 0)) {
        [self.sci message:SCI_MARKERDELETE wParam:line lParam:0];
    } else {
        [self.sci message:SCI_MARKERADD wParam:line lParam:0];
    }
}

- (void)nextBookmark {
    sptr_t line = [self.sci message:SCI_LINEFROMPOSITION wParam:[self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0] lParam:0];
    sptr_t next = [self.sci message:SCI_MARKERNEXT wParam:line + 1 lParam:1 << 0];
    if (next < 0) {
        next = [self.sci message:SCI_MARKERNEXT wParam:0 lParam:1 << 0];
    }
    if (next >= 0) {
        [self.sci message:SCI_GOTOLINE wParam:next lParam:0];
        [self.sci message:SCI_SCROLLCARET wParam:0 lParam:0];
    }
}

- (void)previousBookmark {
    sptr_t line = [self.sci message:SCI_LINEFROMPOSITION wParam:[self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0] lParam:0];
    sptr_t prev = [self.sci message:SCI_MARKERPREVIOUS wParam:line - 1 lParam:1 << 0];
    if (prev < 0) {
        sptr_t total = [self.sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
        prev = [self.sci message:SCI_MARKERPREVIOUS wParam:total - 1 lParam:1 << 0];
    }
    if (prev >= 0) {
        [self.sci message:SCI_GOTOLINE wParam:prev lParam:0];
        [self.sci message:SCI_SCROLLCARET wParam:0 lParam:0];
    }
}

- (void)clearAllBookmarks {
    [self.sci message:SCI_MARKERDELETEALL wParam:0 lParam:0];
}

// ---------------------------------------------------------------------------
#pragma mark - Code Folding
// ---------------------------------------------------------------------------

- (void)foldAll {
    [self.sci message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT lParam:0];
}

- (void)unfoldAll {
    [self.sci message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND lParam:0];
}

- (void)toggleFoldCurrent {
    sptr_t line = [self.sci message:SCI_LINEFROMPOSITION wParam:[self.sci message:SCI_GETCURRENTPOS wParam:0 lParam:0] lParam:0];
    [self.sci message:SCI_TOGGLEFOLD wParam:line lParam:0];
}

// ---------------------------------------------------------------------------
#pragma mark - Line Operations & Text Transformation
// ---------------------------------------------------------------------------

- (void)duplicateLine {
    [self.sci message:SCI_LINEDUPLICATE wParam:0 lParam:0];
}

- (void)deleteLine {
    [self.sci message:SCI_LINEDELETE wParam:0 lParam:0];
}

- (void)moveLineUp {
    [self.sci message:SCI_MOVESELECTEDLINESUP wParam:0 lParam:0];
}

- (void)moveLineDown {
    [self.sci message:SCI_MOVESELECTEDLINESDOWN wParam:0 lParam:0];
}

- (void)joinLines {
    [self.sci message:SCI_LINESJOIN wParam:0 lParam:0];
}

- (void)toUpperCase {
    [self.sci message:SCI_UPPERCASE wParam:0 lParam:0];
}

- (void)toLowerCase {
    [self.sci message:SCI_LOWERCASE wParam:0 lParam:0];
}

- (void)trimTrailingWhitespace {
    ScintillaView *sci = self.sci;
    sptr_t lineCount = [sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
    [sci message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
    for (sptr_t line = lineCount - 1; line >= 0; line--) {
        sptr_t lineStart = [sci message:SCI_POSITIONFROMLINE wParam:line lParam:0];
        sptr_t lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:line lParam:0];
        sptr_t p = lineEnd;
        while (p > lineStart) {
            char ch = (char)[sci message:SCI_GETCHARAT wParam:p - 1 lParam:0];
            if (ch == ' ' || ch == '\t') {
                p--;
            } else {
                break;
            }
        }
        if (p < lineEnd) {
            [sci message:SCI_SETTARGETSTART wParam:p lParam:0];
            [sci message:SCI_SETTARGETEND   wParam:lineEnd lParam:0];
            [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
        }
    }
    [sci message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)toggleCommentWithPrefix:(NSString *)prefix {
    if (prefix.length == 0) return;
    ScintillaView *sci = self.sci;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND   wParam:0 lParam:0];

    sptr_t startLine = [sci message:SCI_LINEFROMPOSITION wParam:selStart lParam:0];
    sptr_t endLine   = [sci message:SCI_LINEFROMPOSITION wParam:selEnd   lParam:0];
    if (selEnd > selStart && [sci message:SCI_POSITIONFROMLINE wParam:endLine lParam:0] == selEnd) {
        endLine--;
    }
    if (endLine < startLine) endLine = startLine;

    const char *pfx = prefix.UTF8String;
    size_t pfxLen = strlen(pfx);

    // Check if all lines are commented
    BOOL allCommented = YES;
    for (sptr_t l = startLine; l <= endLine; l++) {
        sptr_t pos = [sci message:SCI_POSITIONFROMLINE wParam:l lParam:0];
        sptr_t lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:l lParam:0];
        while (pos < lineEnd) {
            char c = (char)[sci message:SCI_GETCHARAT wParam:pos lParam:0];
            if (c != ' ' && c != '\t') break;
            pos++;
        }
        if (pos + pfxLen <= lineEnd) {
            char buf[32] = {0};
            for (size_t i = 0; i < pfxLen && i < sizeof(buf) - 1; i++) {
                buf[i] = (char)[sci message:SCI_GETCHARAT wParam:pos + i lParam:0];
            }
            if (strncmp(buf, pfx, pfxLen) != 0) {
                allCommented = NO;
                break;
            }
        } else {
            allCommented = NO;
            break;
        }
    }

    [sci message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
    for (sptr_t l = endLine; l >= startLine; l--) {
        sptr_t pos = [sci message:SCI_POSITIONFROMLINE wParam:l lParam:0];
        sptr_t lineEnd = [sci message:SCI_GETLINEENDPOSITION wParam:l lParam:0];
        while (pos < lineEnd) {
            char c = (char)[sci message:SCI_GETCHARAT wParam:pos lParam:0];
            if (c != ' ' && c != '\t') break;
            pos++;
        }
        if (allCommented) {
            size_t removeLen = pfxLen;
            if (pos + pfxLen < lineEnd && (char)[sci message:SCI_GETCHARAT wParam:pos + pfxLen lParam:0] == ' ') {
                removeLen++;
            }
            [sci message:SCI_SETTARGETSTART wParam:pos lParam:0];
            [sci message:SCI_SETTARGETEND   wParam:pos + removeLen lParam:0];
            [sci message:SCI_REPLACETARGET  wParam:0 lParam:(sptr_t)""];
        } else {
            NSString *insertStr = [NSString stringWithFormat:@"%@ ", prefix];
            [sci message:SCI_SETTARGETSTART wParam:pos lParam:0];
            [sci message:SCI_SETTARGETEND   wParam:pos lParam:0];
            [sci message:SCI_REPLACETARGET  wParam:-1 lParam:(sptr_t)insertStr.UTF8String];
        }
    }
    [sci message:SCI_ENDUNDOACTION wParam:0 lParam:0];
}

- (void)sortSelectedLinesAscending:(BOOL)ascending {
    ScintillaView *sci = self.sci;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND   wParam:0 lParam:0];

    sptr_t startLine, endLine;
    if (selStart == selEnd) {
        startLine = 0;
        endLine = [sci message:SCI_GETLINECOUNT wParam:0 lParam:0] - 1;
    } else {
        startLine = [sci message:SCI_LINEFROMPOSITION wParam:selStart lParam:0];
        endLine   = [sci message:SCI_LINEFROMPOSITION wParam:selEnd   lParam:0];
        if (selEnd > selStart && [sci message:SCI_POSITIONFROMLINE wParam:endLine lParam:0] == selEnd) {
            endLine--;
        }
    }
    if (endLine <= startLine) return;

    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    for (sptr_t l = startLine; l <= endLine; l++) {
        sptr_t s = [sci message:SCI_POSITIONFROMLINE wParam:l lParam:0];
        sptr_t e = [sci message:SCI_GETLINEENDPOSITION wParam:l lParam:0];
        sptr_t len = e - s;
        char *buf = (char *)malloc(len + 1);
        [sci message:SCI_SETTARGETSTART wParam:s lParam:0];
        [sci message:SCI_SETTARGETEND   wParam:e lParam:0];
        [sci message:SCI_TARGETASUTF8   wParam:0 lParam:(sptr_t)buf];
        buf[len] = '\0';
        [lines addObject:[NSString stringWithUTF8String:buf] ?: @""];
        free(buf);
    }

    [lines sortUsingComparator:^NSComparisonResult(NSString *s1, NSString *s2) {
        if (ascending) {
            return [s1 localizedStandardCompare:s2];
        } else {
            return [s2 localizedStandardCompare:s1];
        }
    }];

    NSString *joined = [lines componentsJoinedByString:@"\n"];
    sptr_t blockStart = [sci message:SCI_POSITIONFROMLINE wParam:startLine lParam:0];
    sptr_t blockEnd   = [sci message:SCI_GETLINEENDPOSITION wParam:endLine lParam:0];

    [sci message:SCI_BEGINUNDOACTION wParam:0 lParam:0];
    [sci message:SCI_SETTARGETSTART wParam:blockStart lParam:0];
    [sci message:SCI_SETTARGETEND   wParam:blockEnd   lParam:0];
    [sci message:SCI_REPLACETARGET  wParam:-1 lParam:(sptr_t)joined.UTF8String];
    [sci message:SCI_ENDUNDOACTION  wParam:0 lParam:0];
}

// ---------------------------------------------------------------------------
#pragma mark - Info
// ---------------------------------------------------------------------------

- (NSInteger)lineCount {
    return (NSInteger)[self.sci message:SCI_GETLINECOUNT wParam:0 lParam:0];
}

- (BOOL)isDirty {
    return [self.sci message:SCI_GETMODIFY wParam:0 lParam:0] != 0;
}

// ---------------------------------------------------------------------------
#pragma mark - Line number margin
// ---------------------------------------------------------------------------

- (void)updateLineNumberMarginWidth {
    ScintillaView *sci = self.sci;
    sptr_t lines = [sci message:SCI_GETLINECOUNT wParam:0 lParam:0];

    int digits = 1;
    sptr_t temp = lines;
    while (temp >= 10) { digits++; temp /= 10; }
    if (digits < 3) digits = 3;

    char buf[16];
    memset(buf, '9', (size_t)digits);
    buf[digits] = '\0';
    sptr_t width = [sci message:SCI_TEXTWIDTH wParam:STYLE_LINENUMBER lParam:(sptr_t)buf];
    width += 12;  // left + right padding
    [sci message:SCI_SETMARGINWIDTHN wParam:0 lParam:width];
}

// ---------------------------------------------------------------------------
#pragma mark - Font & Settings
// ---------------------------------------------------------------------------

- (void)setEditorFont:(NSString *)fontName size:(CGFloat)fontSize {
    ScintillaView *sci = self.sci;
    // Scintilla resolves the face through CoreText.  An unavailable family name
    // silently becomes Helvetica: proportional text whose weight/italic traits
    // are ignored, so bold and italic styles stop working.  Validate first.
    NSString *resolved = fontName;
    if (resolved.length == 0 || [NSFont fontWithName:resolved size:fontSize] == nil) {
        resolved = @"Menlo";
    }
    const char *name = resolved.UTF8String;
    const int sz = (int)lround(fontSize);
    for (int style = 0; style <= STYLE_MAX; style++) {
        [sci message:SCI_STYLESETFONT wParam:style lParam:(sptr_t)name];
        [sci message:SCI_STYLESETSIZE wParam:style lParam:sz];
    }
    [self updateLineNumberMarginWidth];
}

- (void)setTabWidth:(NSInteger)width {
    [self.sci message:SCI_SETTABWIDTH wParam:width lParam:0];
}

- (void)setUseTabs:(BOOL)useTabs {
    [self.sci message:SCI_SETUSETABS wParam:useTabs ? 1 : 0 lParam:0];
}

- (void)setWordWrap:(BOOL)wrap {
    [self.sci message:SCI_SETWRAPMODE wParam:(wrap ? SC_WRAP_WORD : SC_WRAP_NONE) lParam:0];
}

- (void)setShowWhitespace:(BOOL)show {
    [self.sci message:SCI_SETVIEWWS wParam:(show ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE) lParam:0];
}

- (void)setShowIndentGuides:(BOOL)show {
    [self.sci message:SCI_SETINDENTATIONGUIDES wParam:(show ? SC_IV_LOOKBOTH : SC_IV_NONE) lParam:0];
}

// ---------------------------------------------------------------------------
#pragma mark - Bracket Matching (called from SCN_UPDATEUI)
// ---------------------------------------------------------------------------

- (void)handleBracketMatching {
    ScintillaView *sci = self.sci;
    sptr_t pos = [sci message:SCI_GETCURRENTPOS wParam:0 lParam:0];

    static const char *braces = "()[]{}";
    sptr_t bracePos = -1;

    char ch  = (char)[sci message:SCI_GETCHARAT wParam:pos lParam:0];
    char chB = pos > 0 ? (char)[sci message:SCI_GETCHARAT wParam:(pos - 1) lParam:0] : 0;

    if (ch && strchr(braces, ch))        bracePos = pos;
    else if (chB && strchr(braces, chB)) bracePos = pos - 1;

    if (bracePos >= 0) {
        sptr_t matchPos = [sci message:SCI_BRACEMATCH wParam:bracePos lParam:0];
        if (matchPos >= 0) {
            [sci message:SCI_BRACEHIGHLIGHT wParam:bracePos lParam:matchPos];
        } else {
            [sci message:SCI_BRACEBADLIGHT wParam:bracePos lParam:0];
        }
    } else {
        [sci message:SCI_BRACEHIGHLIGHT wParam:(sptr_t)-1 lParam:(sptr_t)-1];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Occurrence Highlight (called from SCN_UPDATEUI)
// ---------------------------------------------------------------------------

/// Debounced entry point. Selection changes arrive for every arrow-key step and
/// every drag update, so wait briefly and only scan once the selection settles.
- (void)scheduleOccurrenceHighlight {
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(updateOccurrenceHighlight)
                                               object:nil];
    [self performSelector:@selector(updateOccurrenceHighlight)
               withObject:nil
               afterDelay:0.04];
}

- (void)clearOccurrenceHighlight {
    ScintillaView *sci = self.sci;
    [sci message:SCI_SETINDICATORCURRENT wParam:INDICATOR_OCCURRENCE lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0
                                        lParam:[sci message:SCI_GETLENGTH wParam:0 lParam:0]];
}

- (void)updateOccurrenceHighlight {
    ScintillaView *sci = self.sci;
    sptr_t selStart = [sci message:SCI_GETSELECTIONSTART wParam:0 lParam:0];
    sptr_t selEnd   = [sci message:SCI_GETSELECTIONEND   wParam:0 lParam:0];
    sptr_t selLen   = selEnd - selStart;

    // A collapsed caret means nothing is selected: drop any old highlight. A
    // very long selection (a whole function, say) would light up most of the
    // document, so it is ignored as well.
    if (selLen <= 0 || selLen > 128) {
        [self clearOccurrenceHighlight];
        return;
    }

    char *needle = (char *)calloc((size_t)selLen + 1, 1);
    if (!needle) {
        return;
    }
    [sci message:SCI_GETSELTEXT wParam:0 lParam:(sptr_t)needle];
    needle[selLen] = '\0';

    // Multi-line selections are not "keywords"; skip them.
    if (needle[0] == '\0' || strchr(needle, '\n') || strchr(needle, '\r')) {
        free(needle);
        [self clearOccurrenceHighlight];
        return;
    }

    NSString *selected = [NSString stringWithUTF8String:needle] ?: @"";

    // Smart case, like Xcode and VS Code: match case only when the selection
    // actually contains an uppercase letter.
    const BOOL hasUpper = ![selected isEqualToString:selected.lowercaseString];

    // Whole-word matching only makes sense for plain identifiers; a phrase or a
    // CJK run is matched literally anywhere.
    BOOL identifier = YES;
    for (const char *p = needle; *p; p++) {
        unsigned char c = (unsigned char)*p;
        if (!(isalnum(c) || c == '_')) {
            identifier = NO;
            break;
        }
    }

    int flags = 0;
    if (hasUpper) flags |= SCFIND_MATCHCASE;
    if (identifier) flags |= SCFIND_WHOLEWORD;

    const sptr_t docLen = [sci message:SCI_GETLENGTH wParam:0 lParam:0];

    [sci message:SCI_SETINDICATORCURRENT wParam:INDICATOR_OCCURRENCE lParam:0];
    [sci message:SCI_INDICATORCLEARRANGE wParam:0 lParam:docLen];

    Sci_TextToFind ttf;
    memset(&ttf, 0, sizeof(ttf));
    ttf.chrg.cpMin = 0;
    ttf.chrg.cpMax = (Sci_PositionCR)docLen;
    ttf.lpstrText = needle;

    // Cap the work on pathological documents (e.g. selecting "e" in a 5 MB
    // log); the visible lines are highlighted long before the cap is reached.
    static const NSInteger maxMatches = 20000;
    NSInteger matched = 0;

    while (ttf.chrg.cpMin < ttf.chrg.cpMax && matched < maxMatches) {
        sptr_t pos = [sci message:SCI_FINDTEXT wParam:flags lParam:(sptr_t)&ttf];
        if (pos < 0) break;

        sptr_t from = ttf.chrgText.cpMin;
        sptr_t to   = ttf.chrgText.cpMax;
        if (to <= from) break;          // never spin on a zero-length match

        [sci message:SCI_INDICATORFILLRANGE wParam:from lParam:to - from];
        ttf.chrg.cpMin = (Sci_PositionCR)to;
        matched++;
    }
    free(needle);
}

// ---------------------------------------------------------------------------
#pragma mark - Auto-indent (called from SCN_CHARADDED)
// ---------------------------------------------------------------------------

- (void)handleAutoIndent:(int)ch {
    if (ch != '\n' && ch != '\r') return;

    ScintillaView *sci = self.sci;
    sptr_t curPos  = [sci message:SCI_GETCURRENTPOS wParam:0 lParam:0];
    sptr_t curLine = [sci message:SCI_LINEFROMPOSITION wParam:curPos lParam:0];
    if (curLine < 1) return;

    sptr_t prevIndent = [sci message:SCI_GETLINEINDENTATION wParam:(curLine - 1) lParam:0];
    if (prevIndent > 0) {
        [sci message:SCI_SETLINEINDENTATION wParam:curLine lParam:prevIndent];
        sptr_t indentPos = [sci message:SCI_GETLINEINDENTPOSITION wParam:curLine lParam:0];
        [sci message:SCI_GOTOPOS wParam:indentPos lParam:0];
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Scintilla Notifications
// ---------------------------------------------------------------------------

- (void)notification:(SCNotification *)notification {
    switch (notification->nmhdr.code) {
        case SCN_MODIFIED: {
            if ((notification->modificationType &
                 (SC_MOD_INSERTTEXT | SC_MOD_DELETETEXT)) != 0) {
                if (self.contentChangeHandler) {
                    self.contentChangeHandler();
                }
                [self updateLineNumberMarginWidth];
            }
            [self updateDirtyState];
            break;
        }
        case SCN_SAVEPOINTREACHED:
        case SCN_SAVEPOINTLEFT:
            [self updateDirtyState];
            break;
        case SCN_UPDATEUI:
            if (notification->updated & SC_UPDATE_SELECTION) {
                [self handleBracketMatching];
                [self scheduleOccurrenceHighlight];
            } else if (notification->updated & SC_UPDATE_CONTENT) {
                [self scheduleOccurrenceHighlight];
            }
            break;
        case SCN_CHARADDED:
            [self handleAutoIndent:notification->ch];
            break;
        case SCN_MARGINCLICK:
            if (notification->margin == 1) {
                sptr_t line = [self.sci message:SCI_LINEFROMPOSITION wParam:notification->position lParam:0];
                sptr_t state = [self.sci message:SCI_MARKERGET wParam:line lParam:0];
                if (state & (1 << 0)) {
                    [self.sci message:SCI_MARKERDELETE wParam:line lParam:0];
                } else {
                    [self.sci message:SCI_MARKERADD wParam:line lParam:0];
                }
            } else if (notification->margin == 2) {
                sptr_t line = [self.sci message:SCI_LINEFROMPOSITION wParam:notification->position lParam:0];
                [self.sci message:SCI_TOGGLEFOLD wParam:line lParam:0];
            }
            break;
        default:
            break;
    }
}

- (void)updateDirtyState {
    const BOOL dirty = self.isDirty;
    if (dirty != self.lastKnownDirty) {
        self.lastKnownDirty = dirty;
        if (self.changeHandler) {
            self.changeHandler(dirty);
        }
    }
}

// ---------------------------------------------------------------------------
#pragma mark - Theme / Appearance
// ---------------------------------------------------------------------------

- (void)applyThemeDark:(BOOL)dark {
    self.darkTheme = dark;

    NSColor *background, *foreground, *dim, *selection, *caretLine, *braceHL;

    if (dark) {
        background = [NSColor colorWithSRGBRed:0.11 green:0.11 blue:0.12 alpha:1.0];
        foreground = [NSColor colorWithSRGBRed:0.87 green:0.87 blue:0.88 alpha:1.0];
        dim        = [NSColor colorWithSRGBRed:0.52 green:0.52 blue:0.55 alpha:1.0];
        selection  = [NSColor colorWithSRGBRed:0.20 green:0.30 blue:0.45 alpha:1.0];
        caretLine  = [NSColor colorWithSRGBRed:0.15 green:0.15 blue:0.16 alpha:1.0];
        braceHL    = [NSColor colorWithSRGBRed:0.25 green:0.40 blue:0.30 alpha:1.0];
    } else {
        // Explicit sRGB values, not dynamic system colours: textBackgroundColor
        // & co. resolve against the system appearance, so with a forced light
        // theme on a dark system they would still come back dark.
        background = [NSColor colorWithSRGBRed:1.00 green:1.00 blue:1.00 alpha:1.0];
        foreground = [NSColor colorWithSRGBRed:0.12 green:0.12 blue:0.14 alpha:1.0];
        dim        = [NSColor colorWithSRGBRed:0.45 green:0.45 blue:0.47 alpha:1.0];
        selection  = [NSColor colorWithSRGBRed:0.66 green:0.80 blue:0.96 alpha:1.0];
        caretLine  = [NSColor colorWithSRGBRed:0.93 green:0.95 blue:0.98 alpha:1.0];
        braceHL    = [NSColor colorWithSRGBRed:0.80 green:0.93 blue:0.80 alpha:1.0];
    }

    const int bg   = ColorRefFromNSColor(background);
    const int fg   = ColorRefFromNSColor(foreground);
    const int dRef = ColorRefFromNSColor(dim);
    const int sel  = ColorRefFromNSColor(selection);
    const int clBg = ColorRefFromNSColor(caretLine);

    ScintillaView *sci = self.sci;

    // Base default style, then propagate to all styles
    [sci message:SCI_STYLESETFORE wParam:STYLE_DEFAULT lParam:fg];
    [sci message:SCI_STYLESETBACK wParam:STYLE_DEFAULT lParam:bg];
    [sci message:SCI_STYLECLEARALL wParam:0 lParam:0];

    // Syntax colours
    [self applySyntaxPaletteDark:dark];

    // Caret, selection, whitespace
    [sci message:SCI_SETCARETFORE      wParam:fg   lParam:0];
    [sci message:SCI_STYLESETFORE      wParam:STYLE_LINENUMBER lParam:dRef];
    [sci message:SCI_STYLESETBACK      wParam:STYLE_LINENUMBER lParam:bg];
    [sci message:SCI_SETSELBACK        wParam:TRUE lParam:sel];
    [sci message:SCI_SETSELFORE        wParam:TRUE lParam:fg];
    [sci message:SCI_SETWHITESPACEFORE wParam:TRUE lParam:dRef];

    // Caret line highlight
    [sci message:SCI_SETCARETLINEBACK  wParam:clBg lParam:0];

    // Margins and fold gutter. The fold margin does not follow STYLE_DEFAULT:
    // it paints a two-tone checkerboard built from the platform chrome
    // colours, which stay light in dark mode. Point both colours at the editor
    // background so the gutter matches the line-number margin.
    [sci message:SCI_SETFOLDMARGINCOLOUR   wParam:1 lParam:bg];
    [sci message:SCI_SETFOLDMARGINHICOLOUR wParam:1 lParam:bg];
    for (int margin = 0; margin <= 2; margin++) {
        [sci message:SCI_SETMARGINBACKN wParam:margin lParam:bg];
    }

    // Folder markers: the marker's fore colour fills the box, the back colour
    // draws its frame, the +/- glyph and the connecting fold lines. The
    // Scintilla default (black fill, white frame/lines) assumes a grey gutter;
    // since the gutter now follows the editor background, white fold lines
    // vanish in the light theme. Use a white box with black frame/lines there,
    // and a grey box with light lines in dark mode.
    const int foldFill = dark ? ColorRefFromNSColor(
        [NSColor colorWithSRGBRed:0.55 green:0.55 blue:0.58 alpha:1.0]) : 0xFFFFFF;
    const int foldLine = dark ? ColorRefFromNSColor(
        [NSColor colorWithSRGBRed:0.75 green:0.75 blue:0.78 alpha:1.0]) : 0x000000;
    for (int marker = SC_MARKNUM_FOLDEREND; marker <= SC_MARKNUM_FOLDEROPEN; marker++) {
        [sci message:SCI_MARKERSETFORE wParam:marker lParam:foldFill];
        [sci message:SCI_MARKERSETBACK wParam:marker lParam:foldLine];
    }

    // Bracket matching styles
    const int brRef = ColorRefFromNSColor(braceHL);
    [sci message:SCI_STYLESETFORE  wParam:STYLE_BRACELIGHT lParam:fg];
    [sci message:SCI_STYLESETBACK  wParam:STYLE_BRACELIGHT lParam:brRef];
    [sci message:SCI_STYLESETBOLD  wParam:STYLE_BRACELIGHT lParam:1];
    [sci message:SCI_STYLESETFORE  wParam:STYLE_BRACEBAD
                             lParam:ColorRefFromNSColor([NSColor systemRedColor])];
    [sci message:SCI_STYLESETBOLD  wParam:STYLE_BRACEBAD lParam:1];

    // Occurrence highlight: a warm amber that stands apart from both the
    // syntax palette and the blue selection, so the current selection and its
    // other occurrences stay distinguishable.
    NSColor *occurrence = dark
        ? [NSColor colorWithSRGBRed:0.95 green:0.72 blue:0.25 alpha:1.0]
        : [NSColor colorWithSRGBRed:0.96 green:0.78 blue:0.30 alpha:1.0];
    [sci message:SCI_INDICSETFORE wParam:INDICATOR_OCCURRENCE
                                 lParam:ColorRefFromNSColor(occurrence)];
}

/// Lexilla assigns style numbers but no colours.  Map the common style indices
/// (C/C++ family, Python, JSON, shell, …) onto a readable palette.
- (void)applySyntaxPaletteDark:(BOOL)dark {
    NSColor *(^rgb)(CGFloat, CGFloat, CGFloat) = ^NSColor *(CGFloat r, CGFloat g, CGFloat b) {
        return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
    };

    NSColor *comment  = dark ? rgb(0.42, 0.60, 0.34) : rgb(0.35, 0.53, 0.30);
    NSColor *keyword  = dark ? rgb(0.34, 0.61, 0.84) : rgb(0.00, 0.20, 0.80);
    NSColor *number   = dark ? rgb(0.71, 0.81, 0.66) : rgb(0.55, 0.20, 0.60);
    NSColor *string   = dark ? rgb(0.81, 0.57, 0.47) : rgb(0.77, 0.10, 0.09);
    NSColor *preproc  = dark ? rgb(0.78, 0.53, 0.75) : rgb(0.60, 0.22, 0.60);
    NSColor *opColor  = dark ? rgb(0.83, 0.83, 0.83) : rgb(0.20, 0.20, 0.20);
    NSColor *typeCol  = dark ? rgb(0.45, 0.80, 0.82) : rgb(0.00, 0.43, 0.48);
    NSColor *funcCol  = dark ? rgb(0.95, 0.80, 0.50) : rgb(0.55, 0.35, 0.00);
    NSColor *attrCol  = dark ? rgb(0.90, 0.68, 0.40) : rgb(0.55, 0.35, 0.05);
    NSColor *varCol   = dark ? rgb(0.80, 0.72, 0.95) : rgb(0.40, 0.20, 0.60);
    NSColor *errorCol = [NSColor systemRedColor];
    NSColor *diffAdd  = dark ? rgb(0.45, 0.80, 0.50) : rgb(0.10, 0.55, 0.15);
    NSColor *diffDel  = dark ? rgb(0.95, 0.50, 0.50) : rgb(0.75, 0.15, 0.10);
    NSColor *diffChg  = dark ? rgb(0.90, 0.75, 0.40) : rgb(0.65, 0.45, 0.00);

    ScintillaView *sci = self.sci;
    void (^set)(int, NSColor *) = ^(int style, NSColor *colour) {
        [sci message:SCI_STYLESETFORE wParam:style lParam:ColorRefFromNSColor(colour)];
    };
    void (^bold)(int, BOOL) = ^(int style, BOOL on) {
        [sci message:SCI_STYLESETBOLD wParam:style lParam:on ? 1 : 0];
    };
    void (^italic)(int, BOOL) = ^(int style, BOOL on) {
        [sci message:SCI_STYLESETITALIC wParam:style lParam:on ? 1 : 0];
    };

    NSString *lexer = self.currentLexer ?: @"null";

    if ([lexer isEqualToString:@"cpp"]) {
        // C / C++ / Objective-C, and the fallback for Java, Go, Swift,
        // JavaScript and TypeScript.
        set(SCE_C_COMMENT, comment);
        set(SCE_C_COMMENTLINE, comment);
        set(SCE_C_COMMENTDOC, comment);
        set(SCE_C_COMMENTLINEDOC, comment);
        set(SCE_C_COMMENTDOCKEYWORD, comment);
        set(SCE_C_COMMENTDOCKEYWORDERROR, errorCol);
        set(SCE_C_NUMBER, number);
        set(SCE_C_WORD, keyword);
        set(SCE_C_WORD2, typeCol);
        set(SCE_C_GLOBALCLASS, typeCol);
        set(SCE_C_STRING, string);
        set(SCE_C_CHARACTER, string);
        set(SCE_C_STRINGEOL, errorCol);
        set(SCE_C_VERBATIM, string);
        set(SCE_C_REGEX, string);
        set(SCE_C_STRINGRAW, string);
        set(SCE_C_TRIPLEVERBATIM, string);
        set(SCE_C_HASHQUOTEDSTRING, string);
        set(SCE_C_USERLITERAL, string);
        set(SCE_C_ESCAPESEQUENCE, string);
        set(SCE_C_UUID, number);
        set(SCE_C_PREPROCESSOR, preproc);
        set(SCE_C_PREPROCESSORCOMMENT, comment);
        set(SCE_C_PREPROCESSORCOMMENTDOC, comment);
        set(SCE_C_OPERATOR, opColor);
        set(SCE_C_TASKMARKER, preproc);

    } else if ([lexer isEqualToString:@"python"]) {
        set(SCE_P_COMMENTLINE, comment);
        set(SCE_P_COMMENTBLOCK, comment);
        set(SCE_P_NUMBER, number);
        set(SCE_P_WORD, keyword);
        set(SCE_P_WORD2, typeCol);
        set(SCE_P_STRING, string);
        set(SCE_P_CHARACTER, string);
        set(SCE_P_TRIPLE, string);
        set(SCE_P_TRIPLEDOUBLE, string);
        set(SCE_P_STRINGEOL, errorCol);
        set(SCE_P_CLASSNAME, typeCol);
        set(SCE_P_DEFNAME, funcCol);
        set(SCE_P_OPERATOR, opColor);
        set(SCE_P_DECORATOR, attrCol);
        set(SCE_P_FSTRING, string);
        set(SCE_P_FCHARACTER, string);
        set(SCE_P_FTRIPLE, string);
        set(SCE_P_FTRIPLEDOUBLE, string);
        set(SCE_P_ATTRIBUTE, attrCol);

    } else if ([lexer isEqualToString:@"json"]) {
        set(SCE_JSON_NUMBER, number);
        set(SCE_JSON_STRING, string);
        set(SCE_JSON_STRINGEOL, errorCol);
        set(SCE_JSON_PROPERTYNAME, attrCol);
        set(SCE_JSON_ESCAPESEQUENCE, string);
        set(SCE_JSON_LINECOMMENT, comment);
        set(SCE_JSON_BLOCKCOMMENT, comment);
        set(SCE_JSON_OPERATOR, opColor);
        set(SCE_JSON_URI, string);
        set(SCE_JSON_COMPACTIRI, string);
        set(SCE_JSON_KEYWORD, keyword);
        set(SCE_JSON_LDKEYWORD, keyword);
        set(SCE_JSON_ERROR, errorCol);

    } else if ([lexer isEqualToString:@"xml"] || [lexer isEqualToString:@"hypertext"]) {
        set(SCE_H_TAG, keyword);
        set(SCE_H_TAGUNKNOWN, keyword);
        set(SCE_H_ATTRIBUTE, attrCol);
        set(SCE_H_ATTRIBUTEUNKNOWN, attrCol);
        set(SCE_H_NUMBER, number);
        set(SCE_H_DOUBLESTRING, string);
        set(SCE_H_SINGLESTRING, string);
        set(SCE_H_OTHER, opColor);
        set(SCE_H_COMMENT, comment);
        set(SCE_H_XCCOMMENT, comment);
        set(SCE_H_ENTITY, preproc);
        set(SCE_H_TAGEND, keyword);
        set(SCE_H_XMLSTART, preproc);
        set(SCE_H_XMLEND, preproc);
        set(SCE_H_SCRIPT, keyword);
        set(SCE_H_ASP, preproc);
        set(SCE_H_ASPAT, preproc);
        set(SCE_H_CDATA, string);
        set(SCE_H_QUESTION, preproc);
        set(SCE_H_VALUE, string);
        set(SCE_H_SGML_DEFAULT, keyword);
        set(SCE_H_SGML_COMMAND, keyword);
        set(SCE_H_SGML_1ST_PARAM, attrCol);
        set(SCE_H_SGML_DOUBLESTRING, string);
        set(SCE_H_SGML_SIMPLESTRING, string);
        set(SCE_H_SGML_ERROR, errorCol);
        set(SCE_H_SGML_SPECIAL, preproc);
        set(SCE_H_SGML_ENTITY, preproc);
        set(SCE_H_SGML_COMMENT, comment);
        set(SCE_H_SGML_1ST_PARAM_COMMENT, comment);
        set(SCE_H_SGML_BLOCK_DEFAULT, keyword);

        // Embedded JavaScript.
        set(SCE_HJ_COMMENT, comment);
        set(SCE_HJ_COMMENTLINE, comment);
        set(SCE_HJ_COMMENTDOC, comment);
        set(SCE_HJ_NUMBER, number);
        set(SCE_HJ_WORD, keyword);
        set(SCE_HJ_KEYWORD, keyword);
        set(SCE_HJ_DOUBLESTRING, string);
        set(SCE_HJ_SINGLESTRING, string);
        set(SCE_HJ_SYMBOLS, opColor);
        set(SCE_HJ_STRINGEOL, errorCol);
        set(SCE_HJ_REGEX, string);
        set(SCE_HJ_TEMPLATELITERAL, string);
        set(SCE_HJA_COMMENT, comment);
        set(SCE_HJA_COMMENTLINE, comment);
        set(SCE_HJA_COMMENTDOC, comment);
        set(SCE_HJA_NUMBER, number);
        set(SCE_HJA_WORD, keyword);
        set(SCE_HJA_KEYWORD, keyword);
        set(SCE_HJA_DOUBLESTRING, string);
        set(SCE_HJA_SINGLESTRING, string);
        set(SCE_HJA_SYMBOLS, opColor);
        set(SCE_HJA_STRINGEOL, errorCol);
        set(SCE_HJA_REGEX, string);
        set(SCE_HJA_TEMPLATELITERAL, string);

        // Embedded PHP.
        set(SCE_HPHP_HSTRING, string);
        set(SCE_HPHP_SIMPLESTRING, string);
        set(SCE_HPHP_WORD, keyword);
        set(SCE_HPHP_NUMBER, number);
        set(SCE_HPHP_VARIABLE, varCol);
        set(SCE_HPHP_COMMENT, comment);
        set(SCE_HPHP_COMMENTLINE, comment);
        set(SCE_HPHP_HSTRING_VARIABLE, varCol);
        set(SCE_HPHP_OPERATOR, opColor);
        set(SCE_HP_COMMENTLINE, comment);
        set(SCE_HP_NUMBER, number);
        set(SCE_HP_STRING, string);
        set(SCE_HP_CHARACTER, string);
        set(SCE_HP_WORD, keyword);
        set(SCE_HP_TRIPLE, string);
        set(SCE_HP_TRIPLEDOUBLE, string);
        set(SCE_HP_CLASSNAME, typeCol);
        set(SCE_HP_DEFNAME, funcCol);
        set(SCE_HP_OPERATOR, opColor);
        set(SCE_HP_IDENTIFIER, opColor);

    } else if ([lexer isEqualToString:@"css"]) {
        set(SCE_CSS_TAG, keyword);
        set(SCE_CSS_CLASS, typeCol);
        set(SCE_CSS_ID, typeCol);
        set(SCE_CSS_PSEUDOCLASS, keyword);
        set(SCE_CSS_PSEUDOELEMENT, keyword);
        set(SCE_CSS_EXTENDED_PSEUDOCLASS, keyword);
        set(SCE_CSS_EXTENDED_PSEUDOELEMENT, keyword);
        set(SCE_CSS_UNKNOWN_PSEUDOCLASS, opColor);
        set(SCE_CSS_OPERATOR, opColor);
        set(SCE_CSS_IDENTIFIER, keyword);
        set(SCE_CSS_IDENTIFIER2, keyword);
        set(SCE_CSS_IDENTIFIER3, keyword);
        set(SCE_CSS_EXTENDED_IDENTIFIER, keyword);
        set(SCE_CSS_UNKNOWN_IDENTIFIER, opColor);
        set(SCE_CSS_VALUE, number);
        set(SCE_CSS_COMMENT, comment);
        set(SCE_CSS_IMPORTANT, preproc);
        set(SCE_CSS_DIRECTIVE, preproc);
        set(SCE_CSS_DOUBLESTRING, string);
        set(SCE_CSS_SINGLESTRING, string);
        set(SCE_CSS_ATTRIBUTE, attrCol);
        set(SCE_CSS_GROUP_RULE, keyword);
        set(SCE_CSS_VARIABLE, varCol);

    } else if ([lexer isEqualToString:@"markdown"]) {
        set(SCE_MARKDOWN_HEADER1, keyword); bold(SCE_MARKDOWN_HEADER1, YES);
        set(SCE_MARKDOWN_HEADER2, keyword); bold(SCE_MARKDOWN_HEADER2, YES);
        set(SCE_MARKDOWN_HEADER3, keyword); bold(SCE_MARKDOWN_HEADER3, YES);
        set(SCE_MARKDOWN_HEADER4, keyword); bold(SCE_MARKDOWN_HEADER4, YES);
        set(SCE_MARKDOWN_HEADER5, keyword); bold(SCE_MARKDOWN_HEADER5, YES);
        set(SCE_MARKDOWN_HEADER6, keyword); bold(SCE_MARKDOWN_HEADER6, YES);
        set(SCE_MARKDOWN_STRONG1, opColor); bold(SCE_MARKDOWN_STRONG1, YES);
        set(SCE_MARKDOWN_STRONG2, opColor); bold(SCE_MARKDOWN_STRONG2, YES);
        set(SCE_MARKDOWN_EM1, opColor); italic(SCE_MARKDOWN_EM1, YES);
        set(SCE_MARKDOWN_EM2, opColor); italic(SCE_MARKDOWN_EM2, YES);
        set(SCE_MARKDOWN_STRIKEOUT, comment);
        set(SCE_MARKDOWN_PRECHAR, comment);
        set(SCE_MARKDOWN_ULIST_ITEM, keyword);
        set(SCE_MARKDOWN_OLIST_ITEM, keyword);
        set(SCE_MARKDOWN_BLOCKQUOTE, comment);
        set(SCE_MARKDOWN_HRULE, comment);
        set(SCE_MARKDOWN_LINK, typeCol);
        set(SCE_MARKDOWN_CODE, string);
        set(SCE_MARKDOWN_CODE2, string);
        set(SCE_MARKDOWN_CODEBK, string);
        set(SCE_MARKDOWN_FRONT_MARK, comment);
        set(SCE_MARKDOWN_FRONT, comment);
        set(SCE_MARKDOWN_FRONT_KEY, attrCol);

    } else if ([lexer isEqualToString:@"bash"]) {
        set(SCE_SH_ERROR, errorCol);
        set(SCE_SH_COMMENTLINE, comment);
        set(SCE_SH_NUMBER, number);
        set(SCE_SH_WORD, keyword);
        set(SCE_SH_STRING, string);
        set(SCE_SH_CHARACTER, string);
        set(SCE_SH_OPERATOR, opColor);
        set(SCE_SH_SCALAR, varCol);
        set(SCE_SH_PARAM, varCol);
        set(SCE_SH_BACKTICKS, string);
        set(SCE_SH_HERE_DELIM, string);
        set(SCE_SH_HERE_Q, string);

    } else if ([lexer isEqualToString:@"sql"]) {
        set(SCE_SQL_COMMENT, comment);
        set(SCE_SQL_COMMENTLINE, comment);
        set(SCE_SQL_COMMENTDOC, comment);
        set(SCE_SQL_NUMBER, number);
        set(SCE_SQL_WORD, keyword);
        set(SCE_SQL_WORD2, typeCol);
        set(SCE_SQL_STRING, string);
        set(SCE_SQL_CHARACTER, string);
        set(SCE_SQL_SQLPLUS, preproc);
        set(SCE_SQL_SQLPLUS_PROMPT, preproc);
        set(SCE_SQL_SQLPLUS_COMMENT, comment);
        set(SCE_SQL_OPERATOR, opColor);
        set(SCE_SQL_COMMENTLINEDOC, comment);
        set(SCE_SQL_COMMENTDOCKEYWORD, comment);
        set(SCE_SQL_COMMENTDOCKEYWORDERROR, errorCol);
        set(SCE_SQL_USER1, typeCol);
        set(SCE_SQL_USER2, typeCol);
        set(SCE_SQL_USER3, typeCol);
        set(SCE_SQL_USER4, typeCol);
        set(SCE_SQL_QUOTEDIDENTIFIER, attrCol);
        set(SCE_SQL_QOPERATOR, opColor);

    } else if ([lexer isEqualToString:@"yaml"]) {
        set(SCE_YAML_COMMENT, comment);
        set(SCE_YAML_IDENTIFIER, attrCol);
        set(SCE_YAML_KEYWORD, keyword);
        set(SCE_YAML_NUMBER, number);
        set(SCE_YAML_REFERENCE, typeCol);
        set(SCE_YAML_DOCUMENT, preproc);
        set(SCE_YAML_TEXT, string);
        set(SCE_YAML_ERROR, errorCol);
        set(SCE_YAML_OPERATOR, opColor);

    } else if ([lexer isEqualToString:@"rust"]) {
        set(SCE_RUST_COMMENTBLOCK, comment);
        set(SCE_RUST_COMMENTLINE, comment);
        set(SCE_RUST_COMMENTBLOCKDOC, comment);
        set(SCE_RUST_COMMENTLINEDOC, comment);
        set(SCE_RUST_NUMBER, number);
        set(SCE_RUST_WORD, keyword);
        set(SCE_RUST_WORD2, typeCol);
        set(SCE_RUST_WORD3, keyword);
        set(SCE_RUST_WORD4, keyword);
        set(SCE_RUST_WORD5, keyword);
        set(SCE_RUST_WORD6, keyword);
        set(SCE_RUST_WORD7, keyword);
        set(SCE_RUST_STRING, string);
        set(SCE_RUST_STRINGR, string);
        set(SCE_RUST_CHARACTER, string);
        set(SCE_RUST_OPERATOR, opColor);
        set(SCE_RUST_IDENTIFIER, opColor);
        set(SCE_RUST_LIFETIME, typeCol);
        set(SCE_RUST_MACRO, funcCol);
        set(SCE_RUST_LEXERROR, errorCol);
        set(SCE_RUST_BYTESTRING, string);
        set(SCE_RUST_BYTESTRINGR, string);
        set(SCE_RUST_BYTECHARACTER, string);
        set(SCE_RUST_CSTRING, string);
        set(SCE_RUST_CSTRINGR, string);

    } else if ([lexer isEqualToString:@"makefile"]) {
        set(SCE_MAKE_COMMENT, comment);
        set(SCE_MAKE_PREPROCESSOR, preproc);
        set(SCE_MAKE_IDENTIFIER, varCol);
        set(SCE_MAKE_OPERATOR, opColor);
        set(SCE_MAKE_TARGET, funcCol);

    } else if ([lexer isEqualToString:@"diff"]) {
        set(SCE_DIFF_COMMENT, comment);
        set(SCE_DIFF_COMMAND, preproc);
        set(SCE_DIFF_HEADER, keyword);
        set(SCE_DIFF_POSITION, typeCol);
        set(SCE_DIFF_DELETED, diffDel);
        set(SCE_DIFF_ADDED, diffAdd);
        set(SCE_DIFF_CHANGED, diffChg);
        set(SCE_DIFF_PATCH_ADD, diffAdd);
        set(SCE_DIFF_PATCH_DELETE, diffDel);
        set(SCE_DIFF_REMOVED_PATCH_ADD, diffChg);
        set(SCE_DIFF_REMOVED_PATCH_DELETE, diffChg);

    } else if ([lexer isEqualToString:@"lua"]) {
        set(SCE_LUA_COMMENT, comment);
        set(SCE_LUA_COMMENTLINE, comment);
        set(SCE_LUA_COMMENTDOC, comment);
        set(SCE_LUA_NUMBER, number);
        set(SCE_LUA_WORD, keyword);
        set(SCE_LUA_WORD2, funcCol);
        set(SCE_LUA_WORD3, funcCol);
        set(SCE_LUA_WORD4, funcCol);
        set(SCE_LUA_WORD5, keyword);
        set(SCE_LUA_WORD6, keyword);
        set(SCE_LUA_WORD7, keyword);
        set(SCE_LUA_WORD8, keyword);
        set(SCE_LUA_STRING, string);
        set(SCE_LUA_CHARACTER, string);
        set(SCE_LUA_LITERALSTRING, string);
        set(SCE_LUA_STRINGEOL, errorCol);
        set(SCE_LUA_PREPROCESSOR, preproc);
        set(SCE_LUA_OPERATOR, opColor);
        set(SCE_LUA_LABEL, typeCol);

    } else if ([lexer isEqualToString:@"ruby"]) {
        set(SCE_RB_ERROR, errorCol);
        set(SCE_RB_COMMENTLINE, comment);
        set(SCE_RB_POD, comment);
        set(SCE_RB_NUMBER, number);
        set(SCE_RB_WORD, keyword);
        set(SCE_RB_WORD_DEMOTED, keyword);
        set(SCE_RB_STDIN, keyword);
        set(SCE_RB_STDOUT, keyword);
        set(SCE_RB_STDERR, keyword);
        set(SCE_RB_CLASSNAME, typeCol);
        set(SCE_RB_MODULE_NAME, typeCol);
        set(SCE_RB_DEFNAME, funcCol);
        set(SCE_RB_OPERATOR, opColor);
        set(SCE_RB_STRING, string);
        set(SCE_RB_CHARACTER, string);
        set(SCE_RB_REGEX, string);
        set(SCE_RB_BACKTICKS, string);
        set(SCE_RB_DATASECTION, string);
        set(SCE_RB_HERE_DELIM, string);
        set(SCE_RB_HERE_Q, string);
        set(SCE_RB_HERE_QQ, string);
        set(SCE_RB_HERE_QX, string);
        set(SCE_RB_STRING_W, string);
        set(SCE_RB_STRING_I, string);
        set(SCE_RB_STRING_QI, string);
        set(SCE_RB_STRING_QS, string);
        set(SCE_RB_GLOBAL, varCol);
        set(SCE_RB_INSTANCE_VAR, varCol);
        set(SCE_RB_CLASS_VAR, varCol);
        set(SCE_RB_SYMBOL, attrCol);

    } else if ([lexer isEqualToString:@"perl"]) {
        set(SCE_PL_ERROR, errorCol);
        set(SCE_PL_COMMENTLINE, comment);
        set(SCE_PL_POD, comment);
        set(SCE_PL_POD_VERB, comment);
        set(SCE_PL_NUMBER, number);
        set(SCE_PL_WORD, keyword);
        set(SCE_PL_STRING, string);
        set(SCE_PL_CHARACTER, string);
        set(SCE_PL_PUNCTUATION, opColor);
        set(SCE_PL_PREPROCESSOR, preproc);
        set(SCE_PL_OPERATOR, opColor);
        set(SCE_PL_SCALAR, varCol);
        set(SCE_PL_ARRAY, varCol);
        set(SCE_PL_HASH, varCol);
        set(SCE_PL_SYMBOLTABLE, varCol);
        set(SCE_PL_VARIABLE_INDEXER, varCol);
        set(SCE_PL_REGEX, string);
        set(SCE_PL_REGSUBST, string);
        set(SCE_PL_LONGQUOTE, string);
        set(SCE_PL_BACKTICKS, string);
        set(SCE_PL_DATASECTION, string);
        set(SCE_PL_HERE_DELIM, string);
        set(SCE_PL_HERE_Q, string);
        set(SCE_PL_HERE_QQ, string);
        set(SCE_PL_HERE_QX, string);
        set(SCE_PL_STRING_Q, string);
        set(SCE_PL_STRING_QQ, string);
        set(SCE_PL_STRING_QX, string);
        set(SCE_PL_STRING_QR, string);
        set(SCE_PL_STRING_QW, string);
        set(SCE_PL_SUB_PROTOTYPE, typeCol);
        set(SCE_PL_FORMAT_IDENT, typeCol);
        set(SCE_PL_FORMAT, string);
        set(SCE_PL_STRING_VAR, varCol);
        set(SCE_PL_XLAT, opColor);

    } else if ([lexer isEqualToString:@"cmake"]) {
        set(SCE_CMAKE_COMMENT, comment);
        set(SCE_CMAKE_STRINGDQ, string);
        set(SCE_CMAKE_STRINGLQ, string);
        set(SCE_CMAKE_STRINGRQ, string);
        set(SCE_CMAKE_STRINGVAR, string);
        set(SCE_CMAKE_COMMANDS, keyword);
        set(SCE_CMAKE_PARAMETERS, attrCol);
        set(SCE_CMAKE_VARIABLE, varCol);
        set(SCE_CMAKE_USERDEFINED, typeCol);
        set(SCE_CMAKE_WHILEDEF, keyword);
        set(SCE_CMAKE_FOREACHDEF, keyword);
        set(SCE_CMAKE_IFDEFINEDEF, keyword);
        set(SCE_CMAKE_MACRODEF, keyword);
        set(SCE_CMAKE_NUMBER, number);

    } else if ([lexer isEqualToString:@"conf"]) {
        set(SCE_CONF_COMMENT, comment);
        set(SCE_CONF_NUMBER, number);
        set(SCE_CONF_IDENTIFIER, attrCol);
        set(SCE_CONF_EXTENSION, typeCol);
        set(SCE_CONF_PARAMETER, attrCol);
        set(SCE_CONF_STRING, string);
        set(SCE_CONF_OPERATOR, opColor);
        set(SCE_CONF_IP, number);
        set(SCE_CONF_DIRECTIVE, keyword);

    } else if ([lexer isEqualToString:@"batch"]) {
        set(SCE_BAT_COMMENT, comment);
        set(SCE_BAT_WORD, keyword);
        set(SCE_BAT_LABEL, funcCol);
        set(SCE_BAT_HIDE, comment);
        set(SCE_BAT_COMMAND, keyword);
        set(SCE_BAT_IDENTIFIER, varCol);
        set(SCE_BAT_OPERATOR, opColor);
    }
}

@end
