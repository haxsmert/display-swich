/// 盖子状态的边沿检测:只认「合 → 开」这一个跳变。
///
/// 为什么需要它:`IOPMrootDomain` 的通知是**电源状态变化**的通知,不是「盖子开了」的通知——
/// 电池、充电、显示器电源等任何变动都会派发,合盖期间它会持续来。
/// 而合盖期间的结论是**恒定**的:内建屏物理不可用,救不了。
/// 若把每一条都当成「内建屏可能可用了」往上抛,上层就得反复查 IOKit、反复算判据、反复写日志,
/// 而答案从头到尾没变过。过滤必须做在事件源这一层,上层才真正不被打扰。
///
/// 只认跳变还有一层意思:**合盖本身不是需要动作的时刻**(它只会让情况变糟,不会让情况变好),
/// 唯一值得叫醒上层的是盖子**打开**的那一瞬——那才是内建屏重新可用的时刻。
public struct LidEdgeDetector {
    private var wasClosed: Bool

    /// `initiallyClosed`:注册监听那一刻的盖子状态,作为比较基线。
    public init(initiallyClosed: Bool) {
        wasClosed = initiallyClosed
    }

    /// 喂入当前盖子状态,返回**是否刚刚发生了「合 → 开」**。
    /// 状态没变、或变成合上,一律返回 false。
    public mutating func didOpen(nowClosed: Bool) -> Bool {
        defer { wasClosed = nowClosed }
        return wasClosed && !nowClosed
    }
}
