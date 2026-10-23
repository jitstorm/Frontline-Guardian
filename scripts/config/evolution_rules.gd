extends RefCounted
## 六条形态路线与三阶解锁配置；夜次从已完成夜数计算，等级来自实际击杀成长。

const FORMS := {
	"echo": {"build": "skill", "name": "回响法阵", "detail": "Q 追加远处七成伤害回响；冷却增加一秒"},
	"nova": {"build": "skill", "name": "环形施法", "detail": "Q 改为自身圆周攻击；伤害降低两成"},
	"chain": {"build": "passive", "name": "连锁雷击", "detail": "三连追击跳向最多三敌；每跳七成伤害"},
	"reaper": {"build": "passive", "name": "收割震波", "detail": "五次命中触发大范围双倍追击"},
	"hunter": {"build": "summon", "name": "游猎幻影", "detail": "单体速射，伤害八成；寿命十秒"},
	"sacrifice": {"build": "summon", "name": "献祭幻影", "detail": "寿命六秒，到期爆炸；不能刷新存活幻影"}
}


## 第零、一、二索引分别对应下一阶一、二、三的最低已完成夜数与英雄等级。
const NIGHTS := [2, 4, 6]
const LEVELS := [2, 4, 7]
const STAGES := {
	"echo": ["回响法阵", "回声扩散", "三重回响"],
	"nova": ["环形施法", "冰环束缚", "护体领域"],
	"chain": ["连锁雷击", "四重电链", "冰电交织"],
	"reaper": ["收割震波", "四击收割", "收割屏障"],
	"hunter": ["游猎幻影", "远距游猎", "分裂猎矢"],
	"sacrifice": ["献祭幻影", "扩散献祭", "灵魂迸发"]
}

## 各路线三阶机制参数；范围单位像素，持续与射击间隔单位秒，伤害为倍率。
## 修改平衡时优先改本表；战场与副本共用规则，避免两张地图出现不同版本。
const MECHANICS := {
	"echo": [{"radius_bonus": 0.0, "echoes": [[120.0, 0.7]]}, {"radius_bonus": 15.0, "echoes": [[120.0, 0.7]]}, {"radius_bonus": 15.0, "echoes": [[120.0, 0.7], [240.0, 0.5]]}],
	"nova": [{"radius": 115.0, "slow": 0.0, "ward": 0.0}, {"radius": 145.0, "slow": 1.0, "ward": 0.0}, {"radius": 145.0, "slow": 1.0, "ward": 2.0}],
	"chain": [{"targets": 3, "range": 180.0, "slow": 0.0}, {"targets": 4, "range": 220.0, "slow": 0.0}, {"targets": 4, "range": 220.0, "slow": 1.0}],
	"reaper": [{"combo": 5, "radius": 140.0, "ward": 0.0}, {"combo": 4, "radius": 140.0, "ward": 0.0}, {"combo": 4, "radius": 165.0, "ward": 1.5}],
	"hunter": [{"range": 360.0, "projectile_life": 0.8, "split_every": 0}, {"range": 450.0, "projectile_life": 0.95, "split_every": 0}, {"range": 450.0, "projectile_life": 0.95, "split_every": 4}],
	"sacrifice": [{"death_radius": 150.0, "radials": 0}, {"death_radius": 180.0, "radials": 0}, {"death_radius": 180.0, "radials": 8}]
}
