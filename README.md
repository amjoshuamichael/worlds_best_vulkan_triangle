# The World's Best Vulkan Triangle

## Quick Start

```bash
git clone --recursive https://codeberg.org/aaaash/worlds_best_vulkan_triangle.git
cd worlds_best_vulkan_triangle
odin run . -debug # make sure you run in debug, debug mode compiles the shaders
```

## Introduction

[You've](https://github.com/SaschaWillems/Vulkan/blob/master/examples/triangle/triangle.cpp) [seen](https://vulkan-tutorial.com/code/15_hello_triangle.cpp) [Vulkan](https://github.com/vulkano-rs/vulkano-examples/blob/master/src/bin/triangle.rs) [triangles](https://gist.github.com/terickson001/bdaa52ce621a6c7f4120abba8959ffe6). The rainbow triangle is usually people's first introduction to Vulkan, and it can be a pretty daunting one. People are often taken aback by the amount of code it takes to draw a triangle. However, I'd argue that, especially for C/C++ code, a lot of these examples have a very low signal-to-noise ratio. 

[Odin](https://odin-lang.org/) puts us in a unique position to write a better triangle. The language's clean syntax makes low-level code much clearer. Odin zeroes struct fields by default, so the tedious work of setting all fields of a configuration or `CreateInfo` struct to zero is unnecessary. Finally, my [Idiomatic Odin-Vulkan bindings library](https://codeberg.org/aaaash/idiomatic_odin_vulkan_bindings) makes many minor improvements to the API. With these changes, I hope the triangle example can be made more clear, and that the code can get closer to the truth of low-level graphics.

This code is designed to be extended into a larger game or application. There are a couple changes to the typical triangle here that I've found useful in my game:
- Pipeline Caching is implemented [properly](https://zeux.io/2019/07/17/serializing-pipeline-cache/).
- The codebase autogenerates `VertexInputAttributeDescription`s using Odin's built-in reflection.
- Swapchain items are structured in `#soa` format so they can be directly written to via the API.
- Error-handling is done through a `try` `proc` group, which wraps vulkan functions quite nicely.
- Shaders are compiled in debug mode, but in release mode, SPIR-V is statically included via `#load`.
