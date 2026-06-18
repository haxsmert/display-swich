import Testing
@testable import DisplaySwitchCore

@Test("构建管道可用")
func buildPipelineWorks() {
    #expect(externalDisplays([]) == [])
}
