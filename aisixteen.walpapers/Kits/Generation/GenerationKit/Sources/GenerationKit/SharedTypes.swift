import Foundation
@_exported import ModelKit

// `AspectRatio` and `ModelIdentity` moved to `ModelKit` in `aisixteen.models`, the base package
// shared with every other on-device generation app here. They are re-exported rather than wrapped:
// call sites throughout the app say `import GenerationKit` and mean "the generation vocabulary",
// and forcing every one of them to learn where a type physically lives would be churn that teaches
// nothing.
//
// The move was not cosmetic. `ModelIdentity` is compared against ids written by the *converter*, in
// that same repository — an id renamed on one side and not the other strands unfinished work on
// someone's device, and the two are now impossible to edit apart.
