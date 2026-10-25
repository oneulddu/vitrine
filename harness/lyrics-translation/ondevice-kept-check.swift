import Foundation
import UIKit

@main
struct OnDeviceKeptCheck {
    static func main() {
        let lines = ["The little blue robot walks through the garden with its friends.", "", "♪"]
        var finished = false
        var passed = false
        // The actual provider's same-language path must need neither downloaded languages nor a
        // TranslationSession. Its nonempty result is the existing saved-translation convention.
        SGOnDeviceTranslation.translate(lines, to: "en") { answer, error in
            passed = answer == lines && error == nil
            print("\(passed ? "PASS" : "FAIL") on-device keeps target-language text as a completed result")
            if let error { print(error) }
            finished = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !finished && deadline.timeIntervalSinceNow > 0 {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        if !finished { print("FAIL on-device completion timed out") }
        exit(finished && passed ? 0 : 1)
    }
}
