# Glass

A structure that defines the configuration of the Liquid Glass material.
`struct Glass`


### Overview
You provide instances of a variant of Liquid Glass to the glassEffect(_:in:) view modifier:

```swift
Text("Hello, World!")
    .font(.title)
    .padding()
    .glassEffect()
```

You can combine Liquid Glass effects using a GlassEffectContainer, which supports morphing views with this effect into each other based on the geometry of their associated views.

