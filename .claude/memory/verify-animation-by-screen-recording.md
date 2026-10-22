---
name: verify-animation-by-screen-recording
description: 动效 / 面板位置类修复,必须真机录屏逐帧看过才说修好;附录屏、拆帧、免手动点按的做法
metadata:
  type: feedback
---

动效、闪跳、面板位置这类问题,**单测和推理都证明不了修好了**,要真机录屏、逐帧看。

**Why:** 2026-10-22 我两次凭推理宣布动效修好(先是「把动画从整行挪到图标」,后是「面板跟随去掉动画」),
他两次截图指出没修好(「这个问题你没修，这个动效还是从上往下滑出来的」)。录屏逐帧一看,才发现
根因根本不在界面层:屏名来源滞后导致行先跳走再跳回;图标窗口会报 1 毫秒的假位置;主屏切换时
全局坐标重算把面板挪到了别处。这些只看代码与日志都推不出完整画面。

**How to apply:**
- 录指定区域 / 整块屏:`screencapture -x -v -V 5 -R x,y,w,h out.mov`,或 `-D <序号>` 录整块屏
  (被关掉的那块屏,录像会在它熄灭时中止)。
- 找变化帧:`ffmpeg -i out.mov -vf "select='gt(scene,0.001)',showinfo" -fps_mode passthrough -f null -`;
  拼逐帧图:`ffmpeg -ss <起> -t <长> -i out.mov -vf "fps=60,crop=...,scale=...,tile=6x4:padding=3:color=red" -frames:v 1 sheet.png`
  (本机 ffmpeg 没有 drawtext,别用)。
- 不用他动手点:辅助功能 `AXFocusedWindow` 下遍历按钮,`AXPress` 面板里的行;按坐标命中测试
  (`AXUIElementCopyElementAtPosition`)时灵时不灵,别依赖。
- 要看「当时程序以为自己在哪」,临时往 scratchpad 写摆放日志,与录像对时;验完撤掉再提交。
- 录屏要动他的屏(开关、换实例):先定兜底,见 [[swapping-running-instance-relights-screens]]、
  [[restore-visibility-before-reporting]]。
