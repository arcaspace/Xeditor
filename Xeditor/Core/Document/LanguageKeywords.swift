import Foundation

/// Keyword lists handed to Lexilla with SCI_SETKEYWORDS.
///
/// Each element is one word-list slot; the index must match the lexer's
/// word-list order (see the lexer sources). Lexilla ships no default keyword
/// lists, so without these every language only gets structural colouring
/// (comments, strings and numbers) but no highlighted keywords.
enum LanguageKeywords {

    static func sets(for language: String) -> [String] {
        switch language {
        case "cpp":        return cpp
        case "objc":       return objc
        case "swift":      return swift
        case "javascript": return javascript
        case "typescript": return typescript
        case "go":         return go
        case "java":       return java
        case "python":     return python
        case "json":       return json
        case "xml":        return html
        case "html":       return html
        case "php":        return html
        case "css":        return css
        case "shell", "bash": return bash
        case "sql":        return sql
        case "yaml":       return yaml
        case "rust":       return rust
        case "lua":        return lua
        case "ruby":       return ruby
        case "perl":       return perl
        case "cmake":      return cmake
        case "makefile":   return makefile
        case "ini":        return conf
        case "batch":      return batch
        default:            return []
        }
    }

    // MARK: - C / C++

    private static let cpp: [String] = [
        """
        alignas alignof and and_eq asm atomic_cancel atomic_commit atomic_noexcept \
        auto bitand bitor bool break case catch char char8_t char16_t char32_t \
        class compl concept const consteval constexpr constinit const_cast continue \
        co_await co_return co_yield decltype default delete do double dynamic_cast \
        else enum explicit export extern false float for friend goto if inline int \
        long mutable namespace new noexcept not not_eq nullptr operator or or_eq \
        private protected public register reinterpret_cast requires return short \
        signed sizeof static static_assert static_cast struct switch template this \
        thread_local throw true try typedef typeid typename union unsigned using \
        virtual void volatile wchar_t while xor xor_eq
        """,
        """
        size_t ptrdiff_t intmax_t uintmax_t int8_t int16_t int32_t int64_t \
        uint8_t uint16_t uint32_t uint64_t intptr_t uintptr_t \
        FILE std string wstring vector map set unordered_map unordered_set \
        list deque array pair tuple optional variant function shared_ptr \
        unique_ptr weak_ptr basic_string string_view span
        """,
        "param return brief note warning see since deprecated",
        """
        std string wstring vector map set unordered_map unordered_set list deque \
        array pair tuple optional variant function shared_ptr unique_ptr weak_ptr \
        size_t ptrdiff_t int8_t int16_t int32_t int64_t uint8_t uint16_t \
        uint32_t uint64_t
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    // MARK: - Objective-C
    // Lexilla has no separate Objective-C lexer; it uses cpp with a wider list.

    private static let objc: [String] = [
        """
        alignas alignof and and_eq asm auto bitand bitor bool break case catch char \
        class compl concept const consteval constexpr const_cast continue \
        co_await co_return co_yield decltype default delete do double dynamic_cast \
        else enum explicit export extern false float for friend goto if inline int \
        long mutable namespace new noexcept not not_eq nullptr operator or or_eq \
        private protected public register reinterpret_cast requires return short \
        signed sizeof static static_assert static_cast struct switch template this \
        thread_local throw true try typedef typeid typename union unsigned using \
        virtual void volatile wchar_t while xor xor_eq \
        interface implementation end protocol property synthesize dynamic selector \
        encode synchronized autoreleasepool import available optional required \
        package instancetype id self super nil Nil YES NO BOOL
        """,
        """
        size_t ptrdiff_t NSInteger NSUInteger CGFloat CFIndex \
        int8_t int16_t int32_t int64_t uint8_t uint16_t uint32_t uint64_t \
        NSString NSMutableString NSArray NSMutableArray NSDictionary \
        NSMutableDictionary NSNumber NSData NSDate NSURL NSError NSView NSWindow \
        NSApplication NSObject
        """,
        "param return brief note warning see since deprecated",
        """
        NSString NSArray NSDictionary NSNumber NSData NSDate NSURL NSError \
        NSView NSWindow NSApplication NSObject NSInteger NSUInteger CGFloat
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    // MARK: - Swift (implemented with the cpp lexer)

    private static let swift: [String] = [
        """
        associatedtype class deinit enum extension fileprivate func import init \
        inout internal let open operator private precedencegroup protocol public \
        rethrows static struct subscript typealias var break case catch continue \
        default defer do else fallthrough for guard if in repeat return switch \
        throw where while as any await false is nil self Self super throws true \
        try async actor some nonisolated isolated consuming borrowing mutating \
        nonmutating override final lazy weak unowned indirect convenience \
        required dynamic optional
        """,
        """
        Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Float Double \
        Bool String Character Array Dictionary Set Optional Result Error Void Any \
        AnyObject Never Substring ClosedRange Range
        """,
        "",
        """
        Equatable Hashable Comparable Identifiable Codable Decodable Encodable \
        CustomStringConvertible CustomDebugStringConvertible Sequence Collection \
        IteratorProtocol ExpressibleByStringLiteral
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    // MARK: - JavaScript / TypeScript (cpp lexer fallback)

    private static let javascript: [String] = [
        """
        async await break case catch class const continue debugger default delete \
        do else export extends finally for function if import in instanceof let \
        new of return static super switch this throw try typeof var void while \
        with yield true false null undefined
        """,
        """
        Array ArrayBuffer BigInt Boolean DataView Date Error EvalError \
        Float32Array Float64Array Function Infinity Int8Array Int16Array \
        Int32Array Intl JSON Map Math NaN Number Object Promise Proxy RangeError \
        ReferenceError Reflect RegExp Set String Symbol SyntaxError TypeError \
        URIError Uint8Array Uint16Array Uint32Array WeakMap WeakSet WebAssembly \
        console document globalThis window
        """,
        "",
        """
        Array ArrayBuffer BigInt Boolean Date Error JSON Map Math Number Object \
        Promise Proxy Reflect RegExp Set String Symbol WeakMap WeakSet
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    private static let typescript: [String] = [
        """
        abstract any as asserts assert async await bigint boolean break case \
        catch class const constructor continue debugger declare default delete \
        do else enum export extends false finally for from function get if \
        implements import in infer instanceof interface is keyof let module \
        namespace never new null number object of out override private protected \
        public readonly require return satisfies set static string super switch \
        symbol this throw true try type typeof undefined unique unknown var void \
        while with yield
        """,
        """
        Array ArrayBuffer BigInt Boolean Date Error Float32Array Float64Array \
        Function Infinity Int8Array Int16Array Int32Array JSON Map Math NaN \
        Number Object Promise Proxy RangeError ReferenceError Reflect RegExp \
        Set String Symbol TypeError Uint8Array Uint16Array Uint32Array \
        WeakMap WeakSet Partial Required Readonly Record Pick Omit Exclude \
        Extract NonNullable Parameters ReturnType InstanceType Awaited
        """,
        "",
        """
        Array BigInt Boolean Date Error JSON Map Number Object Promise RegExp \
        Set String Symbol WeakMap WeakSet
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    // MARK: - Go (cpp lexer fallback)

    private static let go: [String] = [
        """
        break case chan const continue default defer else fallthrough for func go \
        goto if import interface map package range return select struct switch \
        type var true false nil iota
        """,
        """
        bool byte complex64 complex128 error float32 float64 int int8 int16 int32 \
        int64 rune string uint uint8 uint16 uint32 uint64 uintptr any comparable \
        append cap close complex copy delete imag len make new panic print println \
        real recover
        """,
        "",
        """
        bool byte error float32 float64 int int8 int16 int32 int64 rune string \
        uint uint8 uint16 uint32 uint64 uintptr any comparable
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    // MARK: - Java (cpp lexer fallback)

    private static let java: [String] = [
        """
        abstract assert boolean break byte case catch char class const continue \
        default do double else enum extends final finally float for goto if \
        implements import instanceof int interface long native new package \
        private protected public return short static strictfp super switch \
        synchronized this throw throws transient try void volatile while var \
        record sealed permits yield true false null
        """,
        """
        String Object Integer Long Short Byte Character Boolean Double Float \
        Number Void List ArrayList LinkedList Map HashMap TreeMap Set HashSet \
        TreeSet Collection Collections Arrays Optional Stream StringBuilder \
        Thread Exception RuntimeException Error Class System Math
        """,
        "",
        """
        String Object Integer Long Short Byte Character Boolean Double Float \
        Number Void List ArrayList LinkedList Map HashMap TreeMap Set HashSet \
        TreeSet Collection Collections Arrays Optional Stream
        """,
        "",
        "TODO FIXME XXX HACK NOTE"
    ]

    // MARK: - Python

    private static let python: [String] = [
        """
        False None True and as assert async await break class continue def del \
        elif else except finally for from global if import in is lambda \
        nonlocal not or pass raise return try while with yield match case
        """,
        """
        abs all any ascii bin bool breakpoint bytearray bytes callable chr \
        classmethod compile complex delattr dict dir divmod enumerate eval exec \
        filter float format frozenset getattr globals hasattr hash help hex id \
        input int isinstance issubclass iter len list locals map max memoryview \
        min next object oct open ord pow print property range repr reversed \
        round set setattr slice sorted staticmethod str sum super tuple type \
        vars zip __import__
        """
    ]

    // MARK: - JSON

    private static let json: [String] = [
        "true false null",
        "context id type value language graph list set reverse index base vocab container"
    ]

    // MARK: - HTML / XML / PHP
    // LexHTML word-list order: elements+attributes, JavaScript, VBScript,
    // Python, PHP, SGML/DTD.

    private static let html: [String] = [
        """
        a abbr address area article aside audio b base bdi bdo blockquote body br \
        button canvas caption cite code col colgroup data datalist dd del details \
        dfn dialog div dl dt em embed fieldset figcaption figure footer form h1 \
        h2 h3 h4 h5 h6 head header hgroup hr html i iframe img input ins kbd \
        label legend li link main map mark menu meta meter nav noscript object ol \
        optgroup option output p param picture pre progress q rp rt ruby s samp \
        script section select slot small source span strong style sub summary sup \
        table tbody td template textarea tfoot th thead time title tr track u ul \
        var video wbr \
        accept accept-charset accesskey action allow alt as async autocapitalize \
        autocomplete autofocus autoplay charset checked cite class color cols \
        colspan content contenteditable controls coords crossorigin data datetime \
        decoding defer dir dirname disabled download draggable enctype \
        enterkeyhint for form formaction formenctype formmethod formnovalidate \
        formtarget headers height hidden high href hreflang http-equiv id \
        imagesizes imagesrcset importance integrity inputmode is ismap itemprop \
        kind label lang list loading loop low manifest max maxlength media method \
        min minlength multiple muted name nomodule nonce novalidate open optimum \
        pattern ping placeholder playsinline poster preload readonly \
        referrerpolicy rel required reversed role rows rowspan sandbox scope \
        selected shape size sizes slot span spellcheck src srcdoc srclang srcset \
        start step style tabindex target title translate type usemap value width \
        wrap
        """,
        """
        async await break case catch class const continue debugger default delete \
        do else export extends finally for function if import in instanceof let \
        new of return static super switch this throw try typeof var void while \
        with yield true false null undefined
        """,
        """
        and as boolean byref byte call case class const continue debugger dim do \
        each else elseif empty end enum eq event exit false for function get \
        goto if imp implements in is let loop mod new next not nothing null on \
        option optional or private property public raise redim rem resume return \
        select set sub then to true type until wend while with
        """,
        """
        False None True and as assert async await break class continue def del \
        elif else except finally for from global if import in is lambda \
        nonlocal not or pass raise return try while with yield match case
        """,
        """
        __halt_compiler abstract and array as break callable case catch class \
        clone const continue declare default die do echo else elseif empty \
        enddeclare endfor endforeach endif endswitch endwhile eval exit extends \
        final finally fn for foreach function global goto if implements include \
        include_once instanceof insteadof interface isset list match namespace \
        new or print private protected public readonly require require_once \
        return static switch throw trait try unset use var while xor yield true \
        false null
        """,
        """
        DOCTYPE ELEMENT ATTLIST ENTITY NOTATION SYSTEM PUBLIC CDATA ID IDREF \
        IDREFS NMTOKEN NMTOKENS ENTITIES EMPTY ANY PCDATA
        """
    ]

    // MARK: - CSS

    private static let css: [String] = [
        """
        align-content align-items align-self animation animation-delay \
        animation-direction animation-duration animation-fill-mode \
        animation-iteration-count animation-name animation-play-state \
        animation-timing-function appearance azimuth backface-visibility \
        background background-attachment background-clip background-color \
        background-image background-origin background-position background-repeat \
        background-size border border-bottom border-bottom-color \
        border-bottom-left-radius border-bottom-right-radius \
        border-bottom-style border-bottom-width border-collapse border-color \
        border-image border-left border-left-color border-left-style \
        border-left-width border-radius border-right border-right-color \
        border-right-style border-right-width border-spacing border-style \
        border-top border-top-color border-top-left-radius \
        border-top-right-radius border-top-style border-top-width border-width \
        bottom box-shadow box-sizing break-after break-before break-inside \
        caption-side clear clip color column-count column-fill column-gap \
        column-rule column-span column-width columns content counter-increment \
        counter-reset cursor direction display elevation empty-cells filter flex \
        flex-basis flex-direction flex-flow flex-grow flex-shrink flex-wrap float \
        font font-family font-size font-size-adjust font-stretch font-style \
        font-variant font-weight gap grid grid-area grid-auto-columns \
        grid-auto-flow grid-auto-rows grid-column grid-column-end \
        grid-column-gap grid-column-start grid-gap grid-row grid-row-end \
        grid-row-gap grid-row-start grid-template grid-template-areas \
        grid-template-columns grid-template-rows height justify-content \
        justify-items justify-self left letter-spacing line-height list-style \
        list-style-image list-style-position list-style-type margin \
        margin-bottom margin-left margin-right margin-top marker-offset marks \
        max-height max-width min-height min-width object-fit opacity order \
        orphans outline outline-color outline-offset outline-style outline-width \
        overflow overflow-wrap overflow-x overflow-y padding padding-bottom \
        padding-left padding-right padding-top page-break-after \
        page-break-before page-break-inside perspective perspective-origin \
        pointer-events position quotes resize right row-gap size speak \
        speak-header speak-numeral speak-punctuation speech-rate stress \
        tab-size table-layout text-align text-decoration text-indent \
        text-overflow text-rendering text-shadow text-transform top transform \
        transform-origin transform-style transition transition-delay \
        transition-duration transition-property transition-timing-function \
        unicode-bidi user-select vertical-align visibility white-space widows \
        width will-change word-break word-spacing word-wrap z-index
        """,
        """
        active any-link checked default defined disabled empty enabled \
        first-child first-of-type focus focus-visible focus-within hover \
        indeterminate in-range invalid last-child last-of-type link \
        nth-child nth-last-child nth-last-of-type nth-of-type only-child \
        only-of-type optional out-of-range placeholder-shown read-only \
        read-write required root target valid visited
        """,
        "",
        "",
        "after before first-letter first-line marker placeholder selection backdrop",
        """
        -webkit-appearance -webkit-backface-visibility -webkit-background-clip \
        -webkit-background-origin -webkit-background-size -webkit-border-radius \
        -webkit-box-shadow -webkit-filter -webkit-font-smoothing \
        -webkit-mask -webkit-transform -webkit-transition -moz-appearance \
        -moz-border-radius -moz-box-shadow -moz-transform -moz-transition
        """,
        "",
        ""
    ]

    // MARK: - Shell

    private static let bash: [String] = [
        """
        if then else elif fi case esac for select while until do done in function \
        time coproc \
        alias bg bind break builtin caller cd command compgen complete continue \
        declare dirs disown echo enable eval exec exit export false fc fg \
        getopts hash help history jobs kill let local logout mapfile popd printf \
        pushd pwd read readonly return set shift shopt source suspend test trap \
        true type typeset ulimit umask unalias unset wait
        """
    ]

    // MARK: - SQL

    private static let sql: [String] = [
        """
        ADD ALL ALTER AND ANY AS ASC AUTHORIZATION BACKUP BEGIN BETWEEN BIGINT \
        BINARY BIT BLOB BOOLEAN BOTH BREAK BROWSE BULK BY CASCADE CASE CAST CHAR \
        CHARACTER CHECK CHECKPOINT CLOSE CLUSTERED COALESCE COLLATE COLUMN \
        COMMIT COMPUTE CONSTRAINT CONTAINS CONTAINSTABLE CONTINUE CONVERT CREATE \
        CROSS CURRENT CURRENT_DATE CURRENT_TIME CURRENT_TIMESTAMP CURRENT_USER \
        CURSOR DATABASE DBCC DEALLOCATE DECLARE DEFAULT DELETE DENY DESC DISK \
        DISTINCT DISTRIBUTED DOUBLE DROP DUMP ELSE END ERRLVL ESCAPE EXCEPT EXEC \
        EXECUTE EXISTS EXIT EXTERNAL FETCH FILE FILLFACTOR FLOAT FOR FOREIGN \
        FREETEXT FREETEXTTABLE FROM FULL FUNCTION GOTO GRANT GROUP HAVING \
        HOLDLOCK IDENTITY IDENTITY_INSERT IDENTITYCOL IF IN INDEX INNER INSERT \
        INT INTERSECT INTO IS JOIN KEY KILL LEFT LIKE LINENO LOAD MERGE \
        NATIONAL NATURAL NOCOUNT NONCLUSTERED NOT NULL NUMERIC OFF OFFSETS ON \
        OPEN OPENDATASOURCE OPENQUERY OPENROWSET OPENXML OPTION OR ORDER OUTER \
        OVER PERCENT PIVOT PLAN PRECISION PRIMARY PRINT PROC PROCEDURE PUBLIC \
        RAISERROR READ READTEXT REAL RECONFIGURE REFERENCES REPLICATION RESTORE \
        RESTRICT RETURN REVERT REVOKE RIGHT ROLLBACK ROWCOUNT ROWGUIDCOL RULE \
        SAVE SCHEMA SELECT SESSION_USER SET SETUSER SHUTDOWN SMALLINT SOME \
        STATISTICS SYSTEM_USER TABLE TABLESAMPLE TEXTSIZE THEN TO TOP TRAN \
        TRANSACTION TRIGGER TRUNCATE TSEQUAL UNION UNIQUE UNPIVOT UPDATE \
        UPDATETEXT USE USER VALUES VARCHAR VARYING VIEW WAITFOR WHEN WHERE \
        WHILE WITH WRITETEXT
        """,
        "TABLE VIEW INDEX TRIGGER PROCEDURE FUNCTION DATABASE SCHEMA USER ROLE SEQUENCE SYNONYM"
    ]

    // MARK: - YAML

    private static let yaml: [String] = [
        "true false null yes no on off"
    ]

    // MARK: - Rust

    private static let rust: [String] = [
        """
        as break const continue crate else enum extern false fn for if impl in \
        let loop match mod move mut pub ref return self Self static struct super \
        trait true type unsafe use where while async await dyn
        """,
        """
        bool char f32 f64 i8 i16 i32 i64 i128 isize str u8 u16 u32 u64 u128 \
        usize String Vec Option Result Box Rc Arc RefCell Cell HashMap HashSet \
        BTreeMap BTreeSet
        """,
        "crate self Self super macro_rules",
        "",
        "",
        "",
        ""
    ]

    // MARK: - Lua

    private static let lua: [String] = [
        "and break do else elseif end false for function goto if in local nil not or repeat return then true until while",
        """
        assert collectgarbage dofile error getmetatable ipairs load loadfile \
        next pairs pcall print rawequal rawget rawlen rawset require select \
        setmetatable tonumber tostring type xpcall
        """,
        """
        byte char dump find format gmatch gsub len lower match pack rep reverse \
        sub unpack upper concat insert move pack remove sort unpack abs ceil cos \
        deg exp floor fmod huge log max maxinteger min mininteger modf pi rad \
        random randomseed sin sqrt tan tointeger type ult
        """,
        """
        close flush input lines open output popen read seek setvbuf write \
        coroutine create isyieldable resume running status wrap yield os clock \
        date difftime execute exit getenv remove rename setlocale time tmpname
        """
    ]

    // MARK: - Ruby

    private static let ruby: [String] = [
        """
        BEGIN END alias and begin break case class def defined? do else elsif end \
        ensure false for if in module next nil not or redo rescue retry return \
        self super then true undef unless until when while yield __FILE__ \
        __LINE__ __ENCODING__
        """
    ]

    // MARK: - Perl

    private static let perl: [String] = [
        """
        BEGIN END __DATA__ __END__ __FILE__ __LINE__ __PACKAGE__ and cmp continue \
        CORE do else elsif eq for foreach ge gt if last le local lt m ne next no \
        not or our package print printf q qq qr qw qx redo require return s say \
        study sub tr unless until use when while x xor y
        """
    ]

    // MARK: - CMake

    private static let cmake: [String] = [
        """
        add_compile_definitions add_compile_options add_custom_command \
        add_custom_target add_definitions add_dependencies add_executable \
        add_library add_link_options add_subdirectory add_test \
        aux_source_directory break cmake_host_system_information \
        cmake_minimum_required cmake_parse_arguments cmake_path cmake_policy \
        configure_file continue create_test_sourcelist define_property else \
        elseif enable_language enable_testing endforeach endfunction endif \
        endmacro endwhile execute_process file find_file find_library \
        find_package find_path find_program foreach function \
        get_cmake_property get_directory_property get_filename_component \
        get_property if include include_directories \
        include_external_msproject include_guard install link_directories \
        link_libraries list macro mark_as_advanced math message option project \
        return separate_arguments set set_directory_properties set_property \
        site_name source_group string target_compile_definitions \
        target_compile_features target_compile_options \
        target_include_directories target_link_directories \
        target_link_libraries target_link_options target_precompile_headers \
        target_sources try_compile try_run unset variable_watch while
        """,
        "REQUIRED QUIET COMPONENTS OPTIONAL EXCLUDE_FROM_ALL PRIVATE PUBLIC INTERFACE",
        ""
    ]

    // MARK: - Makefile

    private static let makefile: [String] = [
        "define endef export ifdef ifeq ifndef ifneq include override unexport undefine vpath"
    ]

    // MARK: - INI / configuration

    private static let conf: [String] = [
        "include",
        ""
    ]

    // MARK: - Windows batch

    private static let batch: [String] = [
        """
        assoc break call cd chdir cls color copy date del dir echo endlocal erase \
        exit for ftype goto if md mkdir move path pause popd prompt pushd rd rem \
        ren rename rmdir set setlocal shift start time title type ver verify vol
        """,
        """
        attrib chkdsk choice comp compact convert defrag diskcopy doskey expand \
        fc find findstr format label more net ping route runas sort subst \
        systeminfo taskkill tasklist tree xcopy
        """
    ]
}
