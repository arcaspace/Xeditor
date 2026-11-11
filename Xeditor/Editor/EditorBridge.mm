#import "EditorBridge.h"

#import "ScintillaView.h"

#include "Scintilla.h"
#include "ILexer.h"
#include "Lexilla.h"

// Lexilla exports this C entry point; when statically linked we declare it here.
extern "C" Scintilla::ILexer5 *CreateLexer(const char *name);

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

    // Default font
    [sci setFontName:@"SF Mono" size:13 bold:NO italic:NO];

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
    [self applySyntaxPaletteDark:self.darkTheme];
    // No eager SCI_COLOURISE here: after a fresh load Scintilla styles the
    // visible range on paint, which keeps opening large files interactive.
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
    const char *name = fontName.UTF8String;
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
        background = [NSColor textBackgroundColor];
        foreground = [NSColor textColor];
        dim        = [NSColor secondaryLabelColor];
        selection  = [NSColor selectedTextBackgroundColor];
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

    // Bracket matching styles
    const int brRef = ColorRefFromNSColor(braceHL);
    [sci message:SCI_STYLESETFORE  wParam:STYLE_BRACELIGHT lParam:fg];
    [sci message:SCI_STYLESETBACK  wParam:STYLE_BRACELIGHT lParam:brRef];
    [sci message:SCI_STYLESETBOLD  wParam:STYLE_BRACELIGHT lParam:1];
    [sci message:SCI_STYLESETFORE  wParam:STYLE_BRACEBAD
                             lParam:ColorRefFromNSColor([NSColor systemRedColor])];
    [sci message:SCI_STYLESETBOLD  wParam:STYLE_BRACEBAD lParam:1];
}

/// Lexilla assigns style numbers but no colours.  Map the common style indices
/// (C/C++ family, Python, JSON, shell, …) onto a readable palette.
- (void)applySyntaxPaletteDark:(BOOL)dark {
    NSColor *(^rgb)(CGFloat, CGFloat, CGFloat) = ^NSColor *(CGFloat r, CGFloat g, CGFloat b) {
        return [NSColor colorWithSRGBRed:r green:g blue:b alpha:1.0];
    };

    NSColor *comment = dark ? rgb(0.42, 0.60, 0.34) : rgb(0.35, 0.53, 0.30);
    NSColor *keyword = dark ? rgb(0.34, 0.61, 0.84) : rgb(0.00, 0.20, 0.80);
    NSColor *number  = dark ? rgb(0.71, 0.81, 0.66) : rgb(0.55, 0.20, 0.60);
    NSColor *string  = dark ? rgb(0.81, 0.57, 0.47) : rgb(0.77, 0.10, 0.09);
    NSColor *preproc = dark ? rgb(0.78, 0.53, 0.75) : rgb(0.60, 0.22, 0.60);
    NSColor *opColor = dark ? rgb(0.83, 0.83, 0.83) : rgb(0.20, 0.20, 0.20);

    ScintillaView *sci = self.sci;
    const int cComment = ColorRefFromNSColor(comment);
    const int cKeyword = ColorRefFromNSColor(keyword);
    const int cNumber  = ColorRefFromNSColor(number);
    const int cString  = ColorRefFromNSColor(string);
    const int cPreproc = ColorRefFromNSColor(preproc);
    const int cOp      = ColorRefFromNSColor(opColor);

    const struct { int style; int colour; } palette[] = {
        {1, cComment},  {2, cComment},  {3, cComment},  {15, cComment},
        {17, cComment}, {18, cComment}, {23, cComment},
        {4, cNumber},   {8, cNumber},   {14, cNumber},
        {5, cKeyword},  {16, cKeyword}, {19, cKeyword},
        {6, cString},   {7, cString},   {12, cString},
        {13, cString},  {20, cString},  {21, cString},  {22, cString},
        {9, cPreproc},
        {10, cOp},
    };
    for (const auto &entry : palette) {
        [sci message:SCI_STYLESETFORE wParam:entry.style lParam:entry.colour];
    }
}

@end
