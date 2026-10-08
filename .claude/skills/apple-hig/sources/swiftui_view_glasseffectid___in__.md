# glassEffectID(_:in:)

Associates an identity value to Liquid Glass effects defined within this view.
`nonisolated func glassEffectID(_ id: (some Hashable & Sendable)?, in namespace: Namespace.ID) -> some View
`


### Discussion
You use this modifier with the glassEffect(_:in:) view modifier and a GlassEffectContainer view. When used together, SwiftUI uses the identifier to animate shapes to and from each other during transitions.

