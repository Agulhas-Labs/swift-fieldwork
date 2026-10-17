# Coding guidelines — swift-fieldwork

Formatting and mechanical style are enforced by SwiftFormat and SwiftLint (`.swiftformat`,
`.swiftlint.yml`) and are not restated here. What follows is what those tools cannot check:

- **Foundation only, no dependencies.** Every package that depends on this one inherits what it imports.
- **A consumer's identity is a value, never a literal in `Sources`.** Its name, binary, MCP server name, rule
  file and hook subcommands come from the consumer; a type that needs one takes it as a parameter. No type is
  named `Fieldwork`, which would shadow the module.
- **Refuse over guess.** When a config file, a path or a registration is ambiguous or not ours to change,
  report it and change nothing, rather than write a plausible answer. The report says what was done and what
  was not.
- **A doc comment carries no issue number and no date, and each of its paragraphs is one line.**
  `IssueReferenceTests` fails on any `#NN` other than `swift-fieldwork#NN` in every tracked text file, and on
  an ISO date in a `//` comment (Swift) or a whole-line `#` comment (shell). A hard-wrapped `///` paragraph is
  a review point. The issue number goes in the commit message.
- **A test that makes a temporary directory removes it** (`defer`), and writes only inside it.
- **A test that runs git removes every `GIT_*` variable from the child's environment**, and checks that the
  repository it made is inside its own temporary directory before writing to it. A suite run from a git hook
  otherwise writes into the repository being committed to.
- **A test pins an answer's text with a literal, never by calling the helper that renders it.** An
  expectation built from the production helper passes whatever the helper says, so it pins nothing.
- **Public API is versioned from the consumer's view.** An addition is a minor release, a behaviour fix behind
  unchanged signatures is a patch, and anything that breaks a call site is a major. Record each in
  `CHANGELOG.md`.
- **The manifest stays usable as a dependency**: no `unsafeFlags` (SwiftPM refuses them in a package
  resolved by version) and no warnings-as-errors setting (a consumer decides what fails its build).
  Strictness is passed with `-Xswiftc -warnings-as-errors` by the checks.
- **A name or path the privacy gate flags is fixed in the file that holds it.** It goes into
  `Scripts/public-names.txt` only when it is genuinely public, or into the machine's external list
  (`~/.config/fieldwork/public-names.txt`) only when that neighbour is genuinely not a private project, never to
  get a commit through.
