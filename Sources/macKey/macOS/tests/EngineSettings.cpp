//
//  EngineSettings.cpp
//  MacKey tests
//
//  The engine declares its settings as extern ints and expects the host app to define
//  them - on macOS that is AppDelegate.m, which a plain C++ test cannot link against.
//  Defining them here gives the test the same starting configuration a fresh install has
//  (see loadDefaultConfig in AppDelegate.m), and makes it obvious that a test which
//  depends on one of these has to say so.
//

int vCodeTable = 0;             // Unicode
int vInputType = 0;             // Telex
int vFreeMark = 0;
int vCheckSpelling = 1;
int vUseModernOrthography = 0;
int vQuickTelex = 0;
int vRestoreIfWrongSpelling = 0;
int vUseMacro = 1;
int vAutoCapsMacro = 0;
int vUpperCaseFirstChar = 0;
int vAllowConsonantZFWJ = 0;
int vQuickStartConsonant = 0;
int vQuickEndConsonant = 0;
