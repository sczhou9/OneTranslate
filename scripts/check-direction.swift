import Foundation

@main
struct DirectionCheck {
    static func main() {
        var settings = AppSettings()
        settings.sourceLanguage = "Chinese (Traditional)"
        settings.targetLanguage = "English"
        settings.reverseLanguage = "Source language"
        let forward = settings.direction(forSelection: false)
        precondition(forward.source == "Chinese (Traditional)" && forward.target == "English")
        let reverse = settings.direction(forSelection: true)
        precondition(reverse.source == "Auto" && reverse.target == "Chinese (Traditional)")
        settings.reverseLanguage = "Japanese"
        precondition(settings.direction(forSelection: true).target == "Japanese")
        precondition(settings.direction(forSelection: false).target == "English")
        settings.reverseLanguage = "Source language"
        settings.sourceLanguage = "Auto"
        precondition(!settings.direction(forSelection: true).target.isEmpty)
        precondition(settings.direction(forSelection: true).target != "Auto")
        print("PASS: forward, reverse, explicit override, Auto fallback")
    }
}
