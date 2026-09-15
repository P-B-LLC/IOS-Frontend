//
//  LegalDocuments.swift
//  IOS Frontend
//
//  The privacy policy, terms, and licence the App Store requires, and that a
//  person using the app is entitled to read before they agree to it.
//

import Foundation

/// The text of the three documents, and the small amount of information that
/// has to be true about the people publishing them.
///
/// Kept as data rather than as views so the same words can be rendered in the
/// app and published on the web without the two drifting apart. `Legal/` at
/// the repository root holds the web copies, generated from these strings.
///
/// - Important: This text was drafted to describe what the app actually does
///   with data, which is the part that has to be right. It has not been read
///   by a lawyer. Have it reviewed before submitting to the App Store.
enum LegalDocuments {
    /// The address in the documents below.
    ///
    /// - Important: Must be a real, monitored mailbox before submission. App
    ///   Review checks that a privacy contact works, and a person asking for
    ///   their data deleted has a right to reach somebody.
    static let contactEmail = "support@rytivo.app"

    /// The entity the documents are published by.
    ///
    /// - Important: Replace with the registered legal name if the app ships
    ///   under a company rather than an individual developer.
    static let publisher = "Rytivo"

    /// The date the current wording took effect. Update it whenever the text
    /// below changes in substance, not for typographical fixes.
    static let effectiveDate = "15 September 2026"

    static let all: [LegalDocument] = [privacyPolicy, termsOfService, licence]

    // MARK: - Privacy

    static let privacyPolicy = LegalDocument(
        id: "privacy",
        title: "Privacy Policy",
        symbol: "hand.raised",
        summary: "What Rytivo stores, and what it does not do with it.",
        body: """
        Effective \(effectiveDate)

        WHAT THIS COVERS

        This policy covers the Rytivo iOS app and the Rytivo server it talks \
        to. It is written to describe what actually happens to your data, not \
        to reserve rights we do not use.

        THE SHORT VERSION

        Rytivo stores what you put into it so it can show it back to you. It \
        does not contain advertising, analytics, or tracking software, and it \
        does not sell or share your data with anyone.

        One outside service is involved, in one place. When you search for a \
        food, the words you typed are sent to the United States Department of \
        Agriculture's FoodData Central, which is where the nutrition figures \
        come from. That request is made by our server rather than by your \
        phone, and it carries no account, name, or device with it: they are \
        told that somebody looked up "oats", and nothing about who. Searches \
        are cached here, so a common one is often not sent at all.

        WHAT IS STORED

        Your account. A username, an email address, your first and last name, \
        and a password. The password is stored as a one-way hash: nobody, \
        including us, can read it back.

        Your profile. A photo, a short bio, your birthdate, height, weight, \
        target weight, daily step goal, unit preference, time zone, gym, and \
        the disciplines you train. Your height, weight, and target weight are \
        private by default; each has its own switch in your profile that \
        decides whether other people can see it.

        Your training. Workout templates, exercises, sessions, and every set \
        you log, including weights and repetitions. Your body weight history, \
        schedules, cycles, and planner entries.

        Your location, during a session and only then. If you start a run, \
        ride, or swim and grant location access, the app records the route so \
        it can show you distance and pace. It stops when you end the session. \
        Rytivo does not track your location in the background or when no \
        session is running.

        Steps and health data. Your daily step count and step goal. If you \
        connect Apple Health, the app reads the data types you approve in \
        Health's own permission screen. Apple Health data is read to display \
        and record your activity in Rytivo; you can revoke the permission at \
        any time in the Health app.

        Food. Meals and their entries, your nutrition goals, and any meals you \
        save to reuse.

        Gear. Shoes and bikes you add, and the distance recorded against them.

        Social. Posts you write, the photos you attach, the workouts and meals \
        you choose to attach to them, comments, likes, reposts, who you follow, \
        who you block, and reports you file about other people's posts.

        WHO CAN SEE IT

        Most of what you log is visible only to you. What becomes visible to \
        other people is what you post, plus the parts of your profile you \
        switch on. When you post a workout you choose whether to include the \
        weights you logged; leaving that off publishes the workout without the \
        numbers.

        Blocking someone hides your posts from them and theirs from you.

        WHAT IS NOT DONE

        No advertising. No analytics or crash-tracking software that reports \
        your behaviour to a third party. No sale of data. No sharing with data \
        brokers or advertisers. No profiling for marketing.

        SAFETY REVIEW

        With your permission before submission, public-facing text and uploaded \
        photos are sent to OpenAI for automated safety checks. This includes \
        profile names, bios, prompt answers, social handles, public gym details, \
        comments, captions, and titles or instructions in content you choose to \
        share. Account credentials, private measurements and unshared logs are \
        excluded. Avoid including sensitive information in public text. \
        A review copy of an image has its embedded metadata removed. OpenAI's \
        API data controls govern its processing; see \
        https://developers.openai.com/api/docs/guides/your-data. \
        You may cancel a submission instead of permitting review. Automated \
        checks can make mistakes; contact \(contactEmail) to appeal. Human \
        moderators also review reports. Do not email sensitive or illegal images.

        EMAIL

        Rytivo sends email only when it is part of something you asked for, \
        such as a password reset code. It does not send marketing email.

        HOW LONG IT IS KEPT

        Your data is kept while your account exists. Deleting your account \
        from Settings removes your profile and the data associated with it.

        One exception: if a post of yours is reported and a moderator hides it, \
        a record of the report and the decision is kept. A moderation queue \
        that erased its own history could not tell a first complaint from a \
        tenth.

        SECURITY

        Passwords are hashed. Your session credential is held in the iOS \
        keychain rather than in ordinary app storage. Traffic to the server is \
        encrypted. Reset codes are stored hashed and expire after fifteen \
        minutes.

        No system is perfect, and this one is small and new. It is described \
        here so you can judge it rather than assume it.

        CHILDREN

        Rytivo is not intended for children under 13, and accounts should not \
        be created for them. If you believe a child has an account, write to \
        \(contactEmail) and it will be removed.

        YOUR CHOICES

        You can edit or delete anything you have logged from inside the app. \
        You can delete your whole account from Settings, which cannot be \
        undone. You can revoke location and Health permissions in iOS Settings \
        without losing your account.

        To ask what is held about you, or to have it deleted by hand rather \
        than through the app, write to \(contactEmail).

        CHANGES

        If this policy changes in substance, the effective date at the top \
        changes with it and the new version appears here.

        CONTACT

        \(publisher) — \(contactEmail)
        """
    )

    // MARK: - Terms

    static let termsOfService = LegalDocument(
        id: "terms",
        title: "Terms of Service",
        symbol: "doc.text",
        summary: "The rules for using Rytivo and for posting on it.",
        body: """
        Effective \(effectiveDate)

        AGREEING TO THESE TERMS

        Using Rytivo means agreeing to these terms. If you do not agree with \
        them, do not use the app.

        You must be at least 13 years old to have an account.

        YOUR ACCOUNT

        You are responsible for what happens under your account and for \
        keeping your password to yourself. Tell us at \(contactEmail) if you \
        think somebody else has got into it.

        Resetting your password signs out every other device, deliberately.

        WHAT YOU POST

        You keep ownership of what you post. By posting it you give \(publisher) \
        permission to store it and to show it to the people your settings say \
        can see it — which is what publishing a post means, and nothing more. \
        We do not license your content to anybody else.

        You are responsible for having the right to post what you post.

        CONTENT WE DO NOT ALLOW

        There is no tolerance for objectionable content or abusive behaviour on \
        Rytivo. Do not post:

        • Content that harasses, threatens, bullies, or intimidates anybody.
        • Hate speech, or content attacking people over race, ethnicity, \
        national origin, religion, disability, sex, gender identity, sexual \
        orientation, or age.
        • Sexually explicit material, or any sexual content involving minors.
        • Content depicting or encouraging violence, self-harm, or eating \
        disorders. Rytivo is a training app and a place where that content \
        does real damage.
        • Content promoting illegal drugs, or the illegal sale of prescription \
        or performance-enhancing substances.
        • Spam, scams, or impersonation of another person.
        • Anything unlawful, or anything infringing somebody else's rights.

        REPORTING AND MODERATION

        Every post can be reported from the post itself, and any account can be \
        blocked from their profile. Blocking is immediate and needs nobody's \
        approval.

        Reports are reviewed within 24 hours. Content that breaks the rules \
        above is removed, and the account that posted it may be suspended or \
        removed. Accounts that repeatedly post objectionable content are \
        removed.

        This is a commitment about how the service is run, not a promise that \
        nothing objectionable will ever appear. If you see something, report it.

        HEALTH AND TRAINING IS NOT MEDICAL ADVICE

        Rytivo records training, food, and body measurements. It does not give \
        medical advice, and nothing in it is a diagnosis, a treatment, or a \
        substitute for a doctor. Calorie and macro figures are estimates from \
        what you enter.

        Talk to a qualified professional before starting a training or diet \
        programme, particularly if you have a medical condition, are pregnant, \
        or are recovering from an injury. You train at your own risk.

        LOCATION AND SAFETY

        Route tracking runs only during a session you start. Pay attention to \
        where you actually are rather than to the phone.

        ENDING IT

        You can delete your account at any time from Settings. We may suspend \
        or remove an account that breaks these terms, and will do so for the \
        content listed above.

        THE SERVICE AS IT IS

        Rytivo is provided as it is, without warranty. It may be unavailable, \
        it may lose data, and it may change. Keep your own record of anything \
        you cannot afford to lose.

        To the extent the law allows, \(publisher) is not liable for indirect or \
        consequential loss arising from your use of the app. Nothing here \
        limits liability that cannot lawfully be limited.

        CHANGES

        If these terms change in substance, the effective date changes with \
        them and the new version appears here. Continuing to use Rytivo after \
        that means accepting the new version.

        CONTACT

        \(publisher) — \(contactEmail)
        """
    )

    // MARK: - Licence

    static let licence = LegalDocument(
        id: "eula",
        title: "License Agreement",
        symbol: "signature",
        summary: "The licence to use the Rytivo app itself.",
        body: """
        Effective \(effectiveDate)

        THE LICENCE

        \(publisher) grants you a personal, non-transferable, non-exclusive \
        licence to use the Rytivo app on Apple devices you own or control, as \
        permitted by the App Store Terms of Service. You do not own the app; \
        you are licensed to use it.

        WHAT YOU MAY NOT DO

        Do not copy, sell, rent, sublicense, or redistribute the app. Do not \
        reverse-engineer, decompile, or disassemble it except where that right \
        cannot lawfully be excluded. Do not use it to build a competing \
        service, and do not scrape the Rytivo service through it.

        APPLE'S STANDARD AGREEMENT

        This licence is in addition to Apple's Licensed Application End User \
        License Agreement, which applies to apps from the App Store and is \
        available at

        apple.com/legal/internet-services/itunes/dev/stdeula/

        Where the two disagree, Apple's agreement wins on anything it covers.

        Apple is not a party to this licence and has no obligation to support \
        the app. Apple is not responsible for the app, for any claim about it, \
        or for any third-party claim that it infringes intellectual property. \
        Apple and its subsidiaries are third-party beneficiaries of this \
        licence and may enforce it against you.

        USER CONTENT

        Posting on Rytivo is also governed by the Terms of Service, including \
        its rules on objectionable content and the commitment to act on reports \
        within 24 hours.

        SUPPORT

        Support is provided by \(publisher), not by Apple. Write to \
        \(contactEmail).

        TERMINATION

        This licence ends if you break it, or when you stop using the app. \
        Delete the app to end it.

        CONTACT

        \(publisher) — \(contactEmail)
        """
    )
}

/// One of the three documents above.
struct LegalDocument: Identifiable, Hashable {
    let id: String
    let title: String
    /// SF Symbol for the Settings row.
    let symbol: String
    /// One line under the title in Settings, so the row says what it is.
    let summary: String
    let body: String

    /// The body split into headed sections, for rendering.
    ///
    /// A heading is a line in capitals with no lowercase in it. Splitting on
    /// that keeps the source text readable as prose rather than turning it
    /// into a nested array of fragments nobody can proofread.
    var sections: [Section] {
        var sections: [Section] = []
        var heading: String?
        var lines: [String] = []

        func flush() {
            let text = lines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard heading != nil || !text.isEmpty else { return }
            sections.append(Section(heading: heading, text: text))
            lines = []
        }

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if Self.isHeading(trimmed) {
                flush()
                heading = trimmed
            } else {
                lines.append(line)
            }
        }
        flush()
        return sections
    }

    private static func isHeading(_ line: String) -> Bool {
        guard line.count > 2, line.count < 60 else { return false }
        guard line.contains(where: \.isLetter) else { return false }
        return !line.contains(where: \.isLowercase)
    }

    struct Section: Identifiable, Hashable {
        let heading: String?
        let text: String

        var id: String { (heading ?? "") + text.prefix(24) }
    }
}
