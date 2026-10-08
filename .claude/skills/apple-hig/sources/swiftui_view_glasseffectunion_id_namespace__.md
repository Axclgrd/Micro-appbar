# glassEffectUnion(id:namespace:)

Associates any Liquid Glass effects defined within this view to a union with the provided identifier.
`@MainActor @preconcurrency func glassEffectUnion(id: (some Hashable & Sendable)?, namespace: Namespace.ID) -> some View
`


### Discussion
You may want the geometries of multiple views to contribute to a single Liquid Glass effect shape. In these cases, you can use a glassEffectUnion(id:namespace:) to specify that a view should contribute to a union of Liquid Glass effects with a particular identifier. All Liquid Glass effects with the same shape and Liquid Glass variant will be combined into a single shape.

