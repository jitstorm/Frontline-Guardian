# 素材来源与授权

| 文件 | 用途 | 来源与许可 | 署名要求 |
| --- | --- | --- | --- |
| `kenney/tile_*.png` | 英雄、敌人、炮塔、核心、地面及道路 | [Kenney Tiny Dungeon 1.0](https://kenney.nl/assets/tiny-dungeon)，随包 `kenney/LICENSE.txt` 标明 CC0 1.0 | 不强制；此处注明 Kenney |
| `fonts/NotoSansSC-VF.ttf` | 全部游戏内中文绘制 | 本机已安装的 Noto Sans SC 字体副本；[官方项目](https://github.com/google/fonts/tree/main/ofl/notosanssc) 标明 SIL OFL 1.1，许可证见 `fonts/OFL.txt` | 随字体保留许可证及版权声明 |

Kenney 原包主要提供静态图块。当前角色移动以浮动帧表现，攻击和施法沿用弹丸、范围和命中特效，怪物蓄力用预警线、受伤变色、死亡缩小淡出表现。尚未制作独立的逐帧行走、攻击、施法、受伤和死亡序列；这部分不能声称已经完成。

幻影召唤复用 `kenney/tile_0084.png`，通过半透明蓝色染色和程序绘制寿命条区分本体；追击与幻影弹丸使用程序图形。未引入新的第三方素材，继续适用上表许可。

词缀爆炸、连锁雷击、回响法阵、技能形态卡片和震荡预警均由程序绘制，继续使用现有中文字体与 Kenney 图块，没有新增外部素材。
