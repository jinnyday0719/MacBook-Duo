import Metal

enum TestTexture {
    static func makeTexture(device: MTLDevice) -> MTLTexture? {
        let width = 1_600
        let height = 1_000
        var pixels = [UInt8](repeating: 0, count: width * height * 4)

        for y in 0..<height {
            for x in 0..<width {
                var red = 8
                var green = 16
                var blue = 30

                let isGridLine = x % 80 <= 1 || y % 80 <= 1
                if isGridLine {
                    red = 60
                    green = 92
                    blue = 112
                }

                let diagonal = abs((x - y) % 220)
                if diagonal < 3 || diagonal > 217 {
                    red = 34
                    green = 180
                    blue = 186
                }

                if x >= 110 && x < 520 && y >= 470 && y < 780 {
                    red = 246
                    green = 98
                    blue = 54
                }

                let circleX = x - 1_200
                let circleY = y - 690
                if circleX * circleX + circleY * circleY < 125 * 125 {
                    red = 26
                    green = 204
                    blue = 168
                }

                if x >= 920 && x < 1_400 && y >= 150 && y < 360 {
                    let border = x < 924 || x >= 1_396 || y < 154 || y >= 356
                    if border {
                        red = 248
                        green = 248
                        blue = 248
                    }
                }

                let index = (y * width + x) * 4
                pixels[index] = UInt8(red)
                pixels[index + 1] = UInt8(green)
                pixels[index + 2] = UInt8(blue)
                pixels[index + 3] = 255
            }
        }

        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm_srgb,
            width: width,
            height: height,
            mipmapped: false
        )
        descriptor.usage = [.shaderRead]

        guard let texture = device.makeTexture(descriptor: descriptor) else {
            return nil
        }

        pixels.withUnsafeBytes { bytes in
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: bytes.baseAddress!,
                bytesPerRow: width * 4
            )
        }
        return texture
    }
}
