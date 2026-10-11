import Foundation
import NottiSDK

// Reference the SDK so the linker keeps it, but never name the ObjC hook target: the hook must be linked and
// run through the package dependency alone, as it is for an app.
_ = Notti.logLevel

// The counters are read by name so this file needs no import of the bootstrap module.
let hook = NSClassFromString("NottiBootstrap") as? NSObject.Type

func count(_ key: String) -> Int {
    (hook?.value(forKey: key) as? NSNumber)?.intValue ?? -1
}

// -1 means the hook class is not in the binary.
print("NOTTI_HOOK loadCount=\(count("loadCount")) installCount=\(count("installCount"))")
