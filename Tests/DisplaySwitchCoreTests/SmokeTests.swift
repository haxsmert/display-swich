import Testing
@testable import DisplaySwitchCore

@Test("构建管道可用")
func buildPipelineWorks() {
    #expect(DisplaySwitchCore.version == "0.0.1")
}
