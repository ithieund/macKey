//
//  MacroStoreTests.cpp
//  MacKey
//
//  Exercises the engine calls that MacKeyBridge's macro methods sit on top of.
//
//  The bridge is thin, but the save/reload cycle is the part that can lose a user's
//  whole shortcut list: addMacro only touches memory, and the data is persisted by
//  serialising the table with getMacroSaveData and handing the bytes to NSUserDefaults.
//  If that round trip is wrong, everything looks fine until the next launch.
//

#include <cassert>
#include <cstdio>
#include <string>
#include <vector>

#include "Macro.h"

static int failures = 0;

static void expect(bool condition, const char *what) {
    if (condition) {
        printf("  ok   %s\n", what);
    } else {
        printf("  FAIL %s\n", what);
        failures++;
    }
}

static std::vector<std::string> macroTexts() {
    std::vector<std::vector<Uint32>> keys;
    std::vector<std::string> texts, contents;
    getAllMacro(keys, texts, contents);
    return texts;
}

static std::string contentFor(const std::string &text) {
    std::vector<std::vector<Uint32>> keys;
    std::vector<std::string> texts, contents;
    getAllMacro(keys, texts, contents);
    for (size_t i = 0; i < texts.size() && i < contents.size(); i++) {
        if (texts[i] == text) {
            return contents[i];
        }
    }
    return "";
}

int main() {
    printf("empty store\n");
    initMacroMap(nullptr, 0);
    expect(macroTexts().empty(), "starts with no macros");
    expect(!hasMacro("vn"), "reports an unknown macro as missing");

    printf("add and look up\n");
    addMacro("vn", "Việt Nam");
    addMacro("mackey", "MacKey");
    expect(hasMacro("vn"), "finds a macro that was added");
    expect(macroTexts().size() == 2, "both macros are listed");
    expect(contentFor("vn") == "Việt Nam", "keeps non-ASCII content intact");

    printf("adding the same shortcut again replaces it\n");
    addMacro("vn", "Cộng hoà xã hội chủ nghĩa Việt Nam");
    expect(macroTexts().size() == 2, "no duplicate row appears");
    expect(contentFor("vn") == "Cộng hoà xã hội chủ nghĩa Việt Nam", "content was replaced");

    printf("save and reload\n");
    std::vector<Byte> saved;
    getMacroSaveData(saved);
    expect(!saved.empty(), "serialises to something");

    initMacroMap(nullptr, 0);
    expect(macroTexts().empty(), "cleared before reloading");

    initMacroMap(saved.data(), (int)saved.size());
    expect(macroTexts().size() == 2, "both macros came back");
    expect(contentFor("vn") == "Cộng hoà xã hội chủ nghĩa Việt Nam", "content survived the round trip");
    expect(contentFor("mackey") == "MacKey", "the second macro survived too");

    printf("delete\n");
    expect(deleteMacro("vn"), "deleting an existing macro reports success");
    expect(!hasMacro("vn"), "it is gone");
    expect(macroTexts().size() == 1, "the other one is untouched");
    expect(!deleteMacro("nope"), "deleting a missing macro reports failure");

    printf("\n");
    if (failures == 0) {
        printf("Macro store: all assertions passed\n");
        return 0;
    }
    printf("Macro store: %d failure(s)\n", failures);
    return 1;
}
