# GlassEffectContainer

A view that combines multiple Liquid Glass shapes into a single shape that can morph individual shapes into one another.
`@MainActor @preconcurrency struct GlassEffectContainer<Content> where Content : View`


### Overview
Use a container with the glassEffect(_:in:) modifier. Each view with a Liquid Glass effect contributes a shape rendered with the effect to a set of shapes. SwiftUI renders the effects together, improving rendering performance and allowing the effects to interact with and morph into one another.

Configure how shapes interact with one another by customizing the default spacing value of the container. As shapes near one another, their paths start to blend into one another. The higher the spacing, the sooner blending begins as the shapes approach each other.

