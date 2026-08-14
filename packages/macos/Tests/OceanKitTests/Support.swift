/*
 Foundation for the whole test target, in a file that does not import `Testing`.

 Command Line Tools ships `Testing.framework` but not the `_Testing_Foundation`
 cross-import overlay it pulls in when a file imports both, so `import Testing`
 beside `import Foundation` fails to build. Re-exporting it from here keeps
 `Data`, `UUID` and friends visible everywhere without any file importing both.
 */
@_exported import Foundation
