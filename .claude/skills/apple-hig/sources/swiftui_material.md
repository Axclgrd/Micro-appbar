# Material

A background material type.
`struct Material`


### Overview
You can apply a blur effect to a view that appears behind another view by adding a material with the background(_:ignoresSafeAreaEdges:) modifier:

```swift
ZStack {
    Color.teal
    Label("Flag", systemImage: "flag.fill")
        .padding()
        .background(.regularMaterial)
}
```

In the example above, the ZStack layers a Label on top of the color teal. The background modifier inserts the regular material below the label, blurring the part of the background that the label — including its padding — covers:



A material isn’t a view, but adding a material is like inserting a translucent layer between the modified view and its background:



The blurring effect provided by the material isn’t simple opacity. Instead, it uses a platform-specific blending that produces an effect that resembles heavily frosted glass. You can see this more easily with a complex background, like an image:

```swift
ZStack {
    Image("chili_peppers")
        .resizable()
        .aspectRatio(contentMode: .fit)
    Label("Flag", systemImage: "flag.fill")
        .padding()
        .background(.regularMaterial)
}
```



For physical materials, the degree to which the background colors pass through depends on the thickness. The effect also varies with light and dark appearance:



If you need a material to have a particular shape, you can use the background(_:in:fillStyle:) modifier. For example, you can create a material with rounded corners:

```swift
ZStack {
    Color.teal
    Label("Flag", systemImage: "flag.fill")
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
}
```



When you add a material, foreground elements exhibit vibrancy, a context-specific blend of the foreground and background colors that improves contrast. However using foregroundStyle(_:) to set a custom foreground style — excluding the hierarchical styles, like secondary — disables vibrancy.

> **Note** A material blurs a background that’s part of your app, but not what appears behind your app on the screen. For example, the content on the Home Screen doesn’t affect the appearance of a widget.

