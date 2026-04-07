# 战斗机空战：工程师实现指南
**基于 Robert L. Shaw《Fighter Combat: Tactics and Maneuvering》**
*面向 AGL 项目开发者 — 含数学公式、伪代码与数据结构*

---

## 目录

1. [核心几何与坐标系](#1-核心几何与坐标系)
2. [飞行性能模型](#2-飞行性能模型)
3. [武器系统实现](#3-武器系统实现)
4. [基础机动算法 (BFM)](#4-基础机动算法-bfm)
5. [AI 战术决策系统](#5-ai-战术决策系统)
6. [拦截几何计算](#6-拦截几何计算)
7. [编队战术实现](#7-编队战术实现)
8. [感知系统（目视/雷达）](#8-感知系统)
9. [数据结构参考](#9-数据结构参考)
10. [数值参数速查表](#10-数值参数速查表)

---

## 1. 核心几何与坐标系

### 1.1 基础角度定义

所有角度计算的基础——**目标纵横角 (TAA)** 与 **偏尾角 (AOT)**：

```
TAA（Target Aspect Angle）= 目标速度矢量 与 (目标→攻击者) 射线 的夹角

          目标飞行方向
          ↑
          |  TAA=0° (正面迎头)
          |
          +--------→ 射线到攻击者
     TAA=90°(横侧)

          ↓  TAA=180° (正后方，死六点)

AOT（Angle Off Tail）= (攻击者→目标) 射线 与 目标速度矢量 的夹角
  = 180° - TAA

注：AOT=0° 时攻击者在目标正后方（最佳机炮位置）
```

**代码实现：**

```python
import numpy as np

def compute_TAA(target_pos, target_vel, attacker_pos):
    """计算目标纵横角（目标视角下攻击者的方位）"""
    los = attacker_pos - target_pos          # 从目标指向攻击者
    los_dir = los / np.linalg.norm(los)
    tgt_dir = target_vel / np.linalg.norm(target_vel)
    cos_angle = np.clip(np.dot(tgt_dir, los_dir), -1, 1)
    return np.degrees(np.arccos(cos_angle))  # 0°=正面, 180°=死后方

def compute_AOT(target_pos, target_vel, attacker_pos):
    """计算攻击者的偏尾角（攻击者视角）"""
    return 180.0 - compute_TAA(target_pos, target_vel, attacker_pos)

def compute_AON(attacker_pos, attacker_vel, target_pos):
    """计算偏鼻角：目标在攻击者鼻端的偏角"""
    los = target_pos - attacker_pos
    los_dir = los / np.linalg.norm(los)
    att_dir = attacker_vel / np.linalg.norm(attacker_vel)
    cos_angle = np.clip(np.dot(att_dir, los_dir), -1, 1)
    return np.degrees(np.arccos(cos_angle))

def compute_LOS_rate(
    target_pos, target_vel,
    attacker_pos, attacker_vel,
    dt=0.016
):
    """计算视线角速率（导弹制导和机炮瞄准核心）单位: deg/s"""
    def los_angle(tpos, apos):
        d = tpos - apos
        return np.arctan2(d[1], d[0])  # 2D简化

    angle_now = los_angle(target_pos, attacker_pos)
    angle_next = los_angle(
        target_pos + target_vel * dt,
        attacker_pos + attacker_vel * dt
    )
    rate = (angle_next - angle_now) / dt
    return np.degrees(rate)
```

### 1.2 追逐曲线判断

```python
def classify_pursuit(attacker_vel, target_pos, attacker_pos, threshold_deg=5.0):
    """
    判断攻击者当前处于哪种追逐关系
    Returns: "lead" | "pure" | "lag"
    """
    # 攻击者速度矢量方向
    vel_dir = attacker_vel / np.linalg.norm(attacker_vel)
    # 当前视线方向
    los = target_pos - attacker_pos
    los_dir = los / np.linalg.norm(los)

    # 速度矢量超前视线 → lead pursuit
    # 速度矢量落后视线 → lag pursuit
    cross = np.cross(vel_dir[:2], los_dir[:2])  # 2D叉积判断左右
    dot = np.dot(vel_dir, los_dir)
    angle_ahead = np.degrees(np.arccos(np.clip(dot, -1, 1)))

    # 用叉积判断攻击者超前还是落后
    if abs(angle_ahead) < threshold_deg:
        return "pure"
    elif cross > 0:
        return "lead"   # 机头超前目标
    else:
        return "lag"    # 机头落后目标

def compute_lead_angle_required(
    target_pos, target_vel, attacker_pos, attacker_vel, bullet_speed
):
    """
    计算击中目标所需的前置角
    基础弹道计算（忽略重力，适合近距离）
    """
    range_vec = target_pos - attacker_pos
    range_dist = np.linalg.norm(range_vec)

    # 估算子弹飞行时间
    relative_speed = bullet_speed + np.dot(
        attacker_vel / np.linalg.norm(attacker_vel),
        (target_pos - attacker_pos) / range_dist
    )
    tof = range_dist / max(relative_speed, 1.0)

    # 目标未来位置
    target_future = target_pos + target_vel * tof

    # 所需瞄准方向
    aim_dir = target_future - attacker_pos
    aim_dir /= np.linalg.norm(aim_dir)

    vel_dir = attacker_vel / np.linalg.norm(attacker_vel)
    cos_lead = np.clip(np.dot(vel_dir, aim_dir), -1, 1)
    return np.degrees(np.arccos(cos_lead)), tof
```

### 1.3 轨迹交叉角与分离计算

```python
def compute_TCA(vel_a, vel_b):
    """轨迹交叉角 (Track Crossing Angle): 两机速度矢量的夹角"""
    dir_a = vel_a / np.linalg.norm(vel_a)
    dir_b = vel_b / np.linalg.norm(vel_b)
    cos_tca = np.clip(np.dot(dir_a, dir_b), -1, 1)
    return np.degrees(np.arccos(cos_tca))

def compute_flight_path_separation(pos_a, vel_a, pos_b):
    """
    飞行路径间隔：从B点到A飞行路径的垂直距离
    决定领先转弯的收益（关键：书中第76-77页）
    """
    vel_dir = vel_a / np.linalg.norm(vel_a)
    offset = pos_b - pos_a
    # 在vel_dir上的投影
    proj = np.dot(offset, vel_dir) * vel_dir
    perpendicular = offset - proj
    return np.linalg.norm(perpendicular)

def compute_closure_rate(pos_a, vel_a, pos_b, vel_b):
    """接近速率：正值=靠近，负值=远离"""
    los = pos_b - pos_a
    los_dir = los / np.linalg.norm(los)
    relative_vel = vel_a - vel_b
    return np.dot(relative_vel, los_dir)
```

---

## 2. 飞行性能模型

### 2.1 V-n 图与拐角速度

基于书中附录A的物理关系：

```python
class AircraftPerformance:
    """
    飞机性能模型
    基于 Shaw 书中附录的关系式
    """
    def __init__(self, params: dict):
        # 基础参数
        self.max_g        = params['max_g']          # 结构G极限（典型9G）
        self.corner_speed = params['corner_speed']    # 拐角速度 KIAS（典型400-500）
        self.stall_speed  = params['stall_speed']     # 失速速度 KIAS（典型130）
        self.max_speed    = params['max_speed']       # 最大速度 KIAS
        self.wing_loading = params['wing_loading']    # 翼载荷 lb/ft²（影响转弯）
        self.thrust_weight= params['thrust_weight']   # 推重比（影响加速/爬升）
        self.mass         = params['mass']            # 质量 kg
        self.sea_level_ps = params['sea_level_ps']    # 海平面最大Ps ft/s

    def max_instantaneous_g(self, speed_kias: float) -> float:
        """在给定速度下的最大瞬时G（基于V-n图）"""
        if speed_kias < self.stall_speed:
            return 1.0  # 失速
        if speed_kias <= self.corner_speed:
            # 升力限制区域：G与速度平方成正比
            ratio = speed_kias / self.corner_speed
            return self.max_g * (ratio ** 2)
        else:
            # 结构限制区域
            return self.max_g

    def max_sustained_g(self, speed_kias: float, altitude_ft: float) -> float:
        """
        最大持续G（可无限维持的转弯）
        在持续G边界上 Ps = 0
        """
        ps = self.specific_excess_power(speed_kias, altitude_ft, g=1.0)
        # 简化：持续G约为瞬时G的60-70%，受高度影响
        altitude_factor = max(0.4, 1.0 - altitude_ft / 60000.0)
        return min(
            self.max_instantaneous_g(speed_kias),
            self.max_g * 0.65 * altitude_factor
        )

    def turn_radius_ft(self, speed_ktas: float, g: float) -> float:
        """
        转弯半径（英尺）
        RT = V² / (g * G_radial)   ←书中关系式(1)
        """
        v_fps = speed_ktas * 1.6878  # KTAS → ft/s
        g_radial = g * 32.174        # G → ft/s²
        return (v_fps ** 2) / g_radial

    def turn_rate_dps(self, speed_ktas: float, g: float) -> float:
        """
        转弯速率（度/秒）
        TR = g * G / V   ←书中关系式(2)
        """
        v_fps = speed_ktas * 1.6878
        g_radial = g * 32.174
        return np.degrees(g_radial / v_fps)

    def specific_excess_power(
        self, speed_kias: float, altitude_ft: float, g: float = 1.0
    ) -> float:
        """
        比剩余功率 Ps (ft/s)
        Ps = (T - D) * V / W   ←书中附录公式(4)
        正值=可加速/爬升，负值=在失去能量
        """
        # 简化模型：实际应从推力曲线插值
        altitude_factor = max(0.3, 1.0 - altitude_ft / 60000.0)
        thrust_available = self.thrust_weight * altitude_factor

        # 诱导阻力随G增加
        induced_drag_factor = g ** 2 * 0.15

        ps = self.sea_level_ps * altitude_factor * (
            thrust_available - induced_drag_factor
        )
        return ps

    def optimal_corner_speed(self, altitude_ft: float) -> float:
        """
        拐角速度随高度变化
        高海拔时真空速增大但表速不变（书中：拐角速度以表速表示时基本恒定）
        """
        return self.corner_speed  # 以表速KIAS表示时近似恒定

    def energy_state(self, speed_ktas: float, altitude_ft: float) -> float:
        """
        比能量状态 Es (ft)
        Es = H + V²/(2g)   ←书中公式(3)
        """
        v_fps = speed_ktas * 1.6878
        return altitude_ft + (v_fps ** 2) / (2 * 32.174)
```

### 2.2 重力对转弯性能的影响

书中强调垂直/斜向机动中重力的关键作用：

```python
def compute_radial_g(aircraft_g: float, pitch_deg: float, roll_deg: float) -> float:
    """
    实际法向加速度（考虑重力分量）
    书中附录A关键概念：
    - 向下转弯：重力辅助，有效GR增大
    - 向上转弯：对抗重力，有效GR减小
    
    pitch_deg: 俯仰角（正=机头上扬）
    roll_deg:  滚转角（0=水平）
    """
    # 升力矢量贡献
    lift_vertical = aircraft_g * np.cos(np.radians(roll_deg))
    
    # 重力分量（水平转弯时为0，垂直机动时最大）
    gravity_component = np.sin(np.radians(pitch_deg))
    
    # 水平面内的法向加速度
    radial_g = (lift_vertical + gravity_component)
    return radial_g

def nose_low_advantage(speed_ktas: float, pitch_down_deg: float,
                        aircraft: AircraftPerformance) -> float:
    """
    俯冲机动中的转弯半径增益
    书中第86-87页：向下转弯允许在低于拐角速度时也能保持较小转弯半径
    """
    gravity_assist_g = np.sin(np.radians(abs(pitch_down_deg)))
    effective_g = aircraft.max_sustained_g(speed_ktas, 0) + gravity_assist_g
    return aircraft.turn_radius_ft(speed_ktas, effective_g)
```

---

## 3. 武器系统实现

### 3.1 机炮系统

```python
class GunSystem:
    """
    机炮武器系统
    基于 Shaw 第1章
    """
    def __init__(self, params: dict):
        self.muzzle_velocity_fps = params['muzzle_velocity']  # 约3300 ft/s
        self.rate_of_fire_rpm    = params['rate_of_fire']      # 约6000 rpm (M61)
        self.max_range_ft        = params['max_range']         # 约3000 ft
        self.min_range_ft        = params['min_range']         # 约500 ft
        self.dispersion_mrad     = params['dispersion']        # 约5 mrad
        self.ammo_count          = params['ammo_count']

    # ──────────────────────────────────────────
    # 射程判断
    # ──────────────────────────────────────────
    def is_in_range(self, range_ft: float) -> bool:
        return self.min_range_ft <= range_ft <= self.max_range_ft

    # ──────────────────────────────────────────
    # 子弹飞行时间（考虑减速）
    # ──────────────────────────────────────────
    def bullet_tof(self, range_ft: float, shooter_speed_fps: float = 0) -> float:
        """
        子弹飞行时间（秒）
        总初速 = 炮口速度 + 射手速度
        近似线性减速（实际应用弹道表）
        """
        total_v0 = self.muzzle_velocity_fps + shooter_speed_fps
        # 简化：假设平均速度约为初速的85%
        avg_speed = total_v0 * 0.85
        return range_ft / avg_speed

    # ──────────────────────────────────────────
    # 重力下落修正（书中第7-8页）
    # ──────────────────────────────────────────
    def gravity_drop_ft(self, tof: float) -> float:
        """重力下落量（英尺），第一秒约16英尺"""
        return 0.5 * 32.174 * (tof ** 2)

    # ──────────────────────────────────────────
    # 击中概率计算（简化模型）
    # ──────────────────────────────────────────
    def hit_probability(
        self,
        range_ft: float,
        aot_deg: float,
        target_size_ft: float,
        shooter_g: float,
        is_tracking: bool
    ) -> float:
        """
        基于书中讨论的综合命中概率
        
        关键因素：
        - 距离（越近越高）
        - AOT（30°-60°最优，用于跟踪）
        - 射手G载荷（高G降低精度）
        - 跟踪射击 vs 快照
        """
        if not self.is_in_range(range_ft):
            return 0.0

        # 基础命中概率（按距离）
        range_factor = 1.0 - (range_ft - self.min_range_ft) / \
                       (self.max_range_ft - self.min_range_ft)

        # AOT修正（书中：30°-60°最优跟踪区）
        if is_tracking:
            if 30 <= aot_deg <= 60:
                aot_factor = 1.0
            elif aot_deg < 30:
                # 死六点区域也好，前置量小
                aot_factor = 0.9
            else:
                # AOT过大，需要大前置量
                aot_factor = max(0.2, 1.0 - (aot_deg - 60) / 120)
        else:
            # 快照：AOT越大越难
            aot_factor = max(0.1, 1.0 - aot_deg / 180)

        # G载荷影响精度（书中：高G难以稳定瞄准）
        g_factor = max(0.3, 1.0 - (shooter_g - 1.0) / 8.0)

        # 目标大小（呈现面积）
        size_factor = min(1.0, target_size_ft / 50.0)

        base_prob = 0.35 if is_tracking else 0.10
        return base_prob * range_factor * aot_factor * g_factor * size_factor

    # ──────────────────────────────────────────
    # 射击决策：应该开火吗？
    # ──────────────────────────────────────────
    def should_fire(
        self,
        range_ft: float,
        aot_deg: float,
        los_rate_dps: float,
        shooter_g: float
    ) -> tuple[bool, str]:
        """
        Returns (should_fire, reason)
        
        根据书中原则：
        - 跟踪射击：准星稳定后开火
        - 快照：准星扫过时开火（LOS rate高时用快照）
        """
        if not self.is_in_range(range_ft):
            return False, "out_of_range"

        if self.ammo_count <= 0:
            return False, "no_ammo"

        # 视线角速率低 → 可以跟踪射击
        if abs(los_rate_dps) < 10.0:
            # 跟踪射击条件：在30°-60° AOT
            if aot_deg <= 60:
                return True, "tracking_shot"

        # 视线角速率较高 → 快照（书中第20页）
        # 当目标扫过准星时开火
        if abs(los_rate_dps) < 30.0 and aot_deg < 90:
            return True, "snapshot"

        return False, "no_solution"
```

### 3.2 导弹系统

```python
class MissileSystem:
    """
    导弹武器系统
    基于 Shaw 第1章（第31-61页）
    """
    # 制导类型枚举
    PASSIVE_IR   = "passive_ir"      # 被动红外
    ACTIVE_RADAR = "active_radar"    # 主动雷达
    SARH         = "sarh"            # 半主动雷达

    def __init__(self, params: dict):
        self.guidance_type = params['guidance_type']

        # 射程参数（后象限为基准）
        self.max_range_rq_ft   = params['max_range_rq']    # 后象限最大射程
        self.max_range_fq_ft   = params['max_range_fq']    # 前象限最大射程（约5倍RQ）
        self.min_range_ft      = params['min_range']        # 最小射程
        self.min_range_fq_ft   = params.get('min_range_fq', params['min_range'] * 2)

        # 性能参数
        self.max_maneuver_g    = params['max_maneuver_g']  # 导弹最大G（约30-40G）
        self.avg_speed_fps     = params['avg_speed']        # 平均速度
        self.motor_burn_time   = params['burn_time']        # 发动机燃烧时间（秒）
        self.aspect_capability = params['aspect']           # "rq_only" | "all_aspect"

        # 红外特有
        self.ir_band         = params.get('ir_band', 'tailpipe')  # 'tailpipe'|'all'
        self.sun_exclusion_deg = params.get('sun_exclusion', 25)

        # 雷达特有
        self.seeker_range_ft  = params.get('seeker_range', 15000)
        self.lookdown_capable = params.get('lookdown', False)

    # ──────────────────────────────────────────
    # 射程计算（书中图1-9, 1-10, 1-11）
    # ──────────────────────────────────────────
    def compute_max_range(
        self,
        taa_deg: float,              # 目标纵横角
        altitude_ft: float,          # 发射高度
        target_speed_ktas: float,    # 目标速度
        shooter_speed_ktas: float,   # 发射机速度
        target_is_maneuvering: bool = False
    ) -> float:
        """
        计算当前条件下的最大射程
        
        关键：前象限射程远大于后象限（书中约5:1）
        高度显著增大射程（书中图1-10：40000ft约为海平面4倍）
        """
        # 基础射程（按方向插值）
        if taa_deg <= 90:
            # 前象限：线性插值到最大前向射程
            t = taa_deg / 90.0
            base_range = self.max_range_fq_ft * (1.0 - t) + \
                         self.max_range_rq_ft * t
        else:
            # 后象限：线性插值
            t = (taa_deg - 90.0) / 90.0
            base_range = self.max_range_rq_ft

        # 高度修正（书中图1-10）
        # 在40000ft处约为海平面4倍
        altitude_factor = 1.0 + (altitude_ft / 40000.0) * 3.0
        altitude_factor = min(altitude_factor, 4.5)

        # 目标速度修正（书中图1-11）
        # 目标越快，后象限射程越小，前象限越大
        speed_ratio = target_speed_ktas / max(shooter_speed_ktas, 100)
        if taa_deg > 90:  # 后象限
            speed_factor = max(0.5, 2.0 - speed_ratio)
        else:             # 前象限
            speed_factor = min(2.0, speed_ratio)

        # 目标机动影响（书中图1-9右图）
        maneuver_factor = 0.6 if target_is_maneuvering else 1.0

        return base_range * altitude_factor * speed_factor * maneuver_factor

    def compute_min_range(
        self,
        taa_deg: float,
        altitude_ft: float,
        target_speed_ktas: float
    ) -> float:
        """
        最小发射距离
        前象限最小距离更大（关闭速度快，导弹来不及反应）
        书中第54-55页
        """
        base_min = self.min_range_ft
        if taa_deg < 60:
            # 前象限：关闭速度快，最小射程更大
            speed_factor = max(1.0, target_speed_ktas / 300.0)
            altitude_factor = 1.0 + altitude_ft / 40000.0  # 高空导弹反应慢
            return base_min * 2.5 * speed_factor * altitude_factor
        return base_min

    def is_in_launch_envelope(
        self,
        range_ft: float,
        taa_deg: float,
        altitude_ft: float,
        target_speed_ktas: float,
        shooter_speed_ktas: float,
        target_is_maneuvering: bool,
        sun_angle_to_target: float = 180.0,  # 仅红外导弹用
        look_down_angle: float = 0.0         # 仅雷达导弹用
    ) -> tuple[bool, str]:
        """
        返回 (可以发射, 限制原因)
        """
        max_r = self.compute_max_range(
            taa_deg, altitude_ft, target_speed_ktas,
            shooter_speed_ktas, target_is_maneuvering
        )
        min_r = self.compute_min_range(taa_deg, altitude_ft, target_speed_ktas)

        if range_ft > max_r:
            return False, "max_range_exceeded"
        if range_ft < min_r:
            return False, "min_range_not_satisfied"

        # 后象限红外导弹的方向限制（书中第36页）
        if self.aspect_capability == "rq_only" and taa_deg < 60:
            return False, "aspect_limitation"

        # 红外导弹太阳干扰（书中第50页）
        if self.guidance_type == self.PASSIVE_IR:
            if sun_angle_to_target < self.sun_exclusion_deg:
                return False, "sun_in_seeker"

        # 雷达导弹俯视问题（书中第46-47页）
        if self.guidance_type in [self.ACTIVE_RADAR, self.SARH]:
            if not self.lookdown_capable and look_down_angle > 10:
                # 地面杂波问题（横侧方向最严重）
                if 70 < taa_deg < 110:
                    return False, "beam_clutter"

        # 雷达型需要雷达锁定（书中第48页）
        if self.guidance_type == self.SARH:
            # SARH需要发射机持续照射——发射后发射机不能自由机动
            pass  # 由调用方检查雷达锁定状态

        return True, "in_envelope"

    # ──────────────────────────────────────────
    # 比例导引更新（导弹AI）
    # ──────────────────────────────────────────
    def proportional_navigation_command(
        self,
        missile_pos,
        missile_vel,
        target_pos,
        target_vel,
        nav_constant: float = 3.0
    ) -> np.ndarray:
        """
        比例导引律（书中第37-38页）
        
        PN: A_cmd = N * V_closure * omega_LOS
        
        N = 导航常数（通常3-5）
        V_closure = 关闭速度
        omega_LOS = LOS角速率
        
        停止LOS漂移 → 碰撞航向（最优轨迹）
        """
        los = target_pos - missile_pos
        los_dist = np.linalg.norm(los)
        los_dir = los / los_dist

        # 相对速度
        rel_vel = target_vel - missile_vel

        # 关闭速度（沿LOS的分量）
        v_closure = -np.dot(rel_vel, los_dir)

        # LOS角速率（垂直于LOS的分量）
        vel_perp = rel_vel - np.dot(rel_vel, los_dir) * los_dir
        omega_magnitude = np.linalg.norm(vel_perp) / los_dist

        # LOS角速率方向（垂直于LOS的单位矢量）
        if np.linalg.norm(vel_perp) > 1e-6:
            omega_dir = vel_perp / np.linalg.norm(vel_perp)
        else:
            return np.zeros(3)

        # 指令加速度
        accel_magnitude = nav_constant * v_closure * omega_magnitude
        accel_cmd = accel_magnitude * omega_dir

        # 限制到最大可用G
        max_accel = self.max_maneuver_g * 9.81
        if np.linalg.norm(accel_cmd) > max_accel:
            accel_cmd = accel_cmd / np.linalg.norm(accel_cmd) * max_accel

        return accel_cmd

    # ──────────────────────────────────────────
    # 防御：目标是否能规避此导弹？
    # ──────────────────────────────────────────
    def can_evade(
        self,
        time_to_impact: float,
        target_g_available: float,
        target_speed_ktas: float
    ) -> bool:
        """
        书中关键规律（第58页）：
        导弹需要约 5倍目标G 才能拦截做最大G机动的目标
        
        若目标在合适时机开始机动，导弹通常无法跟上
        """
        # 目标最大G机动产生的角速率
        target_turn_rate = (target_g_available * 9.81) / \
                           (target_speed_ktas * 0.5144)  # rad/s

        # 导弹追上所需G（简化模型）
        missile_g_required = target_g_available * 5.0

        if missile_g_required > self.max_maneuver_g:
            return True  # 目标机动超过导弹能力

        # 还需检查时间够不够完成机动（近距来不及）
        if time_to_impact < 1.5:
            return False  # 太晚了

        return False
```

---

## 4. 基础机动算法 (BFM)

### 4.1 高大摆 (High Yo-Yo)

```python
class HighYoYo:
    """
    高大摆机动控制器
    使用场景：AOT约30°-60°，速度接近，即将超越目标（书中第71-73页）
    """

    def __init__(self, aircraft: AircraftPerformance):
        self.aircraft = aircraft
        self.phase = "init"   # init → climb → roll → dive → complete
        self.peak_alt = None

    def should_initiate(
        self,
        range_ft: float,
        aot_deg: float,
        closure_fps: float,
        attacker_speed_ktas: float,
        target_speed_ktas: float
    ) -> bool:
        """判断是否应该执行高大摆"""
        # 条件：AOT适中，速度过快将要超越
        speed_advantage = attacker_speed_ktas - target_speed_ktas
        overshoot_risk = (closure_fps > 200 and range_ft < 3000)
        aot_moderate = 20 < aot_deg < 70

        return aot_moderate and (overshoot_risk or speed_advantage > 100)

    def compute_control_command(
        self,
        attacker_pos, attacker_vel, attacker_speed_ktas,
        target_pos, target_vel,
        current_phase: str
    ) -> dict:
        """
        返回控制指令字典
        {pitch_rate, roll_rate, throttle}
        """
        if current_phase == "init":
            # 第一步：平飞后机翼改平，拉机头向上（离开目标转弯平面）
            return {
                'roll_to_wings_level': True,
                'pitch_rate': +15.0,    # deg/s，向上拉
                'throttle': 1.0,        # 全油门维持速度
                'next_phase_condition': 'climb_initiated'
            }

        elif current_phase == "climb":
            # 第二步：维持爬升，缓慢向目标方向滚转保持视觉
            # 关键：用高度换角度，而不是消耗速度
            los_to_target = target_pos - attacker_pos
            target_bearing = np.arctan2(los_to_target[1], los_to_target[0])

            return {
                'pitch_rate': +8.0,          # 继续轻拉
                'roll_rate': +5.0,           # 向目标方向缓慢滚转（保持视觉）
                'throttle': 0.85,            # 轻微收油维持能量
                'next_phase_condition': 'speed_reduced_to_corner or height_gained'
            }

        elif current_phase == "roll_over":
            # 第三步：在高点滚转向目标（前置/纯/滞后追逐选择）
            # 书中：依据需要的距离选择追逐类型
            return {
                'pitch_rate': -3.0,          # 轻压（翻过顶部）
                'roll_rate': +20.0,          # 滚向目标方向
                'throttle': 1.0,
                'target_pursuit': 'lead',    # 或 pure / lag
                'next_phase_condition': 'nose_on_target_future_position'
            }

        elif current_phase == "dive":
            # 第四步：重力辅助俯冲回目标后方
            return {
                'pitch_rate': -15.0,         # 下压
                'throttle': 0.7,             # 收油防止过速
                'aim_for': 'target_rear_hemisphere',
                'next_phase_condition': 'in_firing_parameters'
            }

        return {'throttle': 1.0}
```

### 4.2 平面剪刀 (Flat Scissors) 决策

```python
class FlatScissorsController:
    """
    平面剪刀机动控制器
    书中第82-86页：慢速、小转弯半径的飞机更有利
    """

    def compute_reversal_timing(
        self,
        my_speed_ktas: float,
        enemy_speed_ktas: float,
        my_aot: float,           # 我方AOT（对敌）
        enemy_aot: float,        # 敌方AOT（对我）
        current_sep_ft: float    # 当前鼻尾距离
    ) -> dict:
        """
        决定何时翻转
        书中关键：越早翻转 → TCA越小 → 更好角度（但范围更小）
        """
        # 慢速飞机可以更早翻转（书中第83-84页）
        speed_ratio = my_speed_ktas / max(enemy_speed_ktas, 1)

        # 理想翻转时机：当我方可以指向敌方时（有角度优势）
        # 书中：角度越大，可越早翻转
        if my_aot < 30 and speed_ratio < 0.95:
            # 我在内圈，速度更慢，立即翻转
            reversal_urgency = "immediate"
            expected_tca = 30  # 度
        elif my_aot < 60:
            reversal_urgency = "soon"
            expected_tca = 60
        else:
            # 延迟翻转获得更大鼻尾距离
            reversal_urgency = "delayed"
            expected_tca = 90

        # 翻转后的预期鼻尾距离（书中图2-17）
        if reversal_urgency == "immediate":
            expected_sep_after = current_sep_ft * 0.3  # 很小，危险但有效
        elif reversal_urgency == "soon":
            expected_sep_after = current_sep_ft * 0.6
        else:
            expected_sep_after = current_sep_ft * 0.9

        return {
            'reversal_urgency': reversal_urgency,
            'expected_tca_deg': expected_tca,
            'expected_separation_ft': expected_sep_after,
            'decelerate_for_advantage': speed_ratio > 1.05  # 快速时应减速
        }

    def should_enter_scissors(
        self,
        my_speed_ktas: float,
        enemy_speed_ktas: float,
        my_wing_loading: float,
        enemy_wing_loading: float
    ) -> bool:
        """
        是否应该主动进入剪刀战？
        书中：低翼载（慢速）飞机的最佳战场
        """
        speed_advantage = my_speed_ktas < enemy_speed_ktas  # 我慢有利
        wl_advantage = my_wing_loading < enemy_wing_loading  # 我翼载低有利

        # 书中第85页：高速飞机应避免剪刀战
        if my_speed_ktas > enemy_speed_ktas * 1.1:
            return False  # 不利，速度太快

        return wl_advantage or speed_advantage
```

### 4.3 领先转弯 (Lead Turn)

```python
def compute_lead_turn_opportunity(
    my_pos, my_vel, my_turn_radius_ft: float,
    enemy_pos, enemy_vel,
    enemy_turn_radius_ft: float
) -> dict:
    """
    计算领先转弯的收益
    书中第74-77页：飞行路径间隔决定领先转弯的价值
    
    当间隔 < 我方转弯半径：速度是关键因素
    当间隔 ≈ 一个直径：转弯半径是关键
    当间隔 > 一个直径：几乎无优势
    """
    separation_ft = compute_flight_path_separation(my_pos, my_vel, enemy_pos)

    if separation_ft < my_turn_radius_ft:
        primary_factor = "speed"
        advantage_deg = min(180, 180 * (1 - my_turn_radius_ft / max(separation_ft, 1)))
    elif separation_ft < 2 * my_turn_radius_ft:
        primary_factor = "turn_radius"
        radius_ratio = enemy_turn_radius_ft / my_turn_radius_ft
        advantage_deg = min(90, 90 * (radius_ratio - 1.0))
    else:
        primary_factor = "none"
        advantage_deg = 0

    # 书中：早转弯有超越风险
    tca_at_overshoot = max(0, 90 - advantage_deg / 2)

    # 何时开始转弯（以距离的倍数来表示）
    optimal_start_range = my_turn_radius_ft * 2

    return {
        'should_lead_turn': advantage_deg > 15,
        'expected_advantage_deg': advantage_deg,
        'primary_factor': primary_factor,
        'optimal_start_range_ft': optimal_start_range,
        'tca_at_overshoot_deg': tca_at_overshoot,
        'overshoot_risk': separation_ft < my_turn_radius_ft * 0.5
    }
```

---

## 5. AI 战术决策系统

### 5.1 主决策状态机

```python
from enum import Enum, auto

class TacticalState(Enum):
    # 进攻状态
    ANGLES_FIGHT       = auto()  # 角度战
    ENERGY_FIGHT       = auto()  # 能量战
    PRESS_ATTACK       = auto()  # 压制攻击（已有优势）
    FIRE_GUN           = auto()  # 开炮
    FIRE_MISSILE       = auto()  # 发射导弹

    # 机动状态
    HIGH_YO_YO         = auto()  # 高大摆
    LOW_YO_YO          = auto()  # 低大摆
    LAG_ROLL           = auto()  # 滞后翻滚
    BARREL_ROLL_ATTACK = auto()  # 桶滚攻击
    FLAT_SCISSORS      = auto()  # 平面剪刀
    ROLLING_SCISSORS   = auto()  # 滚转剪刀
    LEAD_TURN          = auto()  # 领先转弯

    # 防御状态
    BREAK_TURN         = auto()  # 急转弯防御
    JINK               = auto()  # 急动防御
    EXTEND_ESCAPE      = auto()  # 延伸脱离
    DEFENSIVE_SPIRAL   = auto()  # 防御螺旋
    FLARE_CHAFF        = auto()  # 施放干扰

    # 其他
    DISENGAGE          = auto()  # 脱离交战
    INTERCEPT          = auto()  # 截击过程中


class FighterAI:
    """
    战斗机战术AI主控制器
    实现 Shaw 书中的战术决策逻辑
    """

    def __init__(self, aircraft: AircraftPerformance, weapons: dict):
        self.aircraft = aircraft
        self.gun      = weapons.get('gun')
        self.missiles = weapons.get('missiles', [])
        self.state    = TacticalState.INTERCEPT
        self.state_timer = 0.0

    def update(self, situation: dict, dt: float) -> dict:
        """
        每帧调用，返回控制指令
        situation 包含：我方状态、敌方状态、环境
        """
        self.state_timer += dt

        # 计算态势参数
        params = self._compute_situation_params(situation)

        # ─── 最高优先级：生存威胁检测 ───
        if params['incoming_missile']:
            new_state = self._choose_missile_defense(params)
            if new_state != self.state:
                self.state = new_state
                self.state_timer = 0.0

        # ─── 武器发射窗口 ───
        elif params['in_gun_envelope'] and params['aot_deg'] < 30:
            self.state = TacticalState.FIRE_GUN

        elif params['best_missile'] and params['in_missile_envelope']:
            self.state = TacticalState.FIRE_MISSILE

        # ─── 战术决策 ───
        else:
            new_state = self._choose_offensive_tactic(params)
            if new_state != self.state or self.state_timer > 8.0:
                self.state = new_state
                self.state_timer = 0.0

        return self._execute_state(params)

    def _compute_situation_params(self, situation: dict) -> dict:
        """计算所有战术相关参数"""
        my  = situation['self']
        tgt = situation['target']

        range_ft = np.linalg.norm(tgt['pos'] - my['pos']) * 3.281  # m→ft

        params = {
            # 几何
            'range_ft'     : range_ft,
            'aot_deg'      : compute_AOT(tgt['pos'], tgt['vel'], my['pos']),
            'aon_deg'      : compute_AON(my['pos'], my['vel'], tgt['pos']),
            'tca_deg'      : compute_TCA(my['vel'], tgt['vel']),
            'los_rate_dps' : compute_LOS_rate(tgt['pos'], tgt['vel'],
                                              my['pos'], my['vel']),
            'closure_fps'  : compute_closure_rate(my['pos'], my['vel'],
                                                  tgt['pos'], tgt['vel']) * 3.281,
            'separation_ft': compute_flight_path_separation(
                                my['pos'], my['vel'], tgt['pos']) * 3.281,

            # 能量态势
            'my_energy'    : self.aircraft.energy_state(
                                my['speed_ktas'], my['altitude_ft']),
            'tgt_energy'   : self.aircraft.energy_state(
                                tgt.get('speed_ktas', 300),
                                tgt.get('altitude_ft', 20000)),
            'my_ps'        : self.aircraft.specific_excess_power(
                                my['speed_ktas'], my['altitude_ft'],
                                my.get('current_g', 1.0)),
            'altitude_diff_ft': my['altitude_ft'] - tgt.get('altitude_ft', 20000),

            # 速度态势
            'my_speed_ktas': my['speed_ktas'],
            'tgt_speed_ktas': tgt.get('speed_ktas', 300),
            'speed_advantage': my['speed_ktas'] - tgt.get('speed_ktas', 300),
            'at_corner_speed': abs(my['speed_ktas'] - self.aircraft.corner_speed) < 30,

            # 武器状态
            'in_gun_envelope': (self.gun and
                                self.gun.is_in_range(range_ft)),
            'best_missile'   : self._select_best_missile(situation),
            'in_missile_envelope': False,  # 下面填充

            # 威胁
            'incoming_missile': situation.get('missile_warning', False),
            'missile_toi'    : situation.get('missile_toi', 99.0),

            # 追逐关系
            'pursuit_type'   : classify_pursuit(
                                  my['vel'], tgt['pos'], my['pos']),
        }

        # 检查最优导弹包线
        if params['best_missile']:
            in_env, reason = params['best_missile'].is_in_launch_envelope(
                range_ft,
                compute_TAA(tgt['pos'], tgt['vel'], my['pos']),
                my['altitude_ft'],
                tgt.get('speed_ktas', 300),
                my['speed_ktas'],
                tgt.get('is_maneuvering', False)
            )
            params['in_missile_envelope'] = in_env

        return params

    def _choose_offensive_tactic(self, p: dict) -> TacticalState:
        """
        核心战术决策逻辑
        基于 Shaw 第3章（同型飞机）和第4章（异型飞机）
        """
        aot       = p['aot_deg']
        range_ft  = p['range_ft']
        energy_advantage = p['my_energy'] - p['tgt_energy']
        speed_adv = p['speed_advantage']
        closure   = p['closure_fps']

        # ─── 阶段一：已有有利位置，压制 ───
        if aot < 20 and range_ft < 2000:
            return TacticalState.PRESS_ATTACK

        # ─── 阶段二：即将超越目标（高速 + 近距 + 中等AOT）───
        if closure > 300 and range_ft < 2500 and 15 < aot < 60:
            # 高大摆：防止超越（书中第71页）
            return TacticalState.HIGH_YO_YO

        # ─── 阶段三：远距滞后位置，需要拉近 ───
        if aot > 60 and range_ft > 4000 and p['pursuit_type'] == 'lag':
            # 低大摆：用高度换角度（书中第73页）
            return TacticalState.LOW_YO_YO

        # ─── 阶段四：前象限接近（对向）───
        if aot > 120 or p['tca_deg'] > 120:
            # 领先转弯（书中第74页）
            if p['separation_ft'] > 0:
                return TacticalState.LEAD_TURN

        # ─── 阶段五：战术方向选择 ───
        # 角度战条件：低翼载或需要近身（书中第99-100页）
        angles_preferred = (
            self.aircraft.wing_loading < 50 or      # 低翼载优势
            energy_advantage < -5000                 # 能量处于劣势
        )
        # 能量战条件：有速度/高度优势（书中第104页）
        energy_preferred = (
            speed_adv > 100 or
            p['altitude_diff_ft'] > 3000 or
            energy_advantage > 5000
        )

        if angles_preferred and not energy_preferred:
            # 角度战：鼻对鼻转弯，保持近距
            return TacticalState.ANGLES_FIGHT
        elif energy_preferred:
            # 能量战：用能量优势换位置
            return TacticalState.ENERGY_FIGHT
        else:
            # 中性：默认角度战（更快）
            return TacticalState.ANGLES_FIGHT

    def _choose_missile_defense(self, p: dict) -> TacticalState:
        """
        导弹防御决策
        书中第58-61页
        """
        toi = p['missile_toi']

        if toi > 8.0:
            # 时间充裕：机动 + 施放干扰
            return TacticalState.FLARE_CHAFF
        elif toi > 3.0:
            # 时间适中：最大G急转弯
            return TacticalState.BREAK_TURN
        else:
            # 紧急：离面桶滚
            return TacticalState.JINK

    def _execute_state(self, p: dict) -> dict:
        """将状态转化为飞行控制指令"""
        cmd = {
            'throttle': 1.0,
            'pitch_rate': 0.0,   # deg/s
            'roll_rate': 0.0,    # deg/s
            'g_command': 1.0,    # 目标G
            'fire_gun': False,
            'fire_missile': False,
            'jettison_stores': False,
        }

        if self.state == TacticalState.FIRE_GUN:
            cmd['fire_gun'] = True
            cmd['g_command'] = min(4.0, p['aot_deg'] / 10)  # 轻拉跟踪

        elif self.state == TacticalState.FIRE_MISSILE:
            cmd['fire_missile'] = True
            # 发射前稳定
            cmd['g_command'] = 2.0

        elif self.state == TacticalState.ANGLES_FIGHT:
            # 角度战：鼻对鼻转弯，使用俯冲角保持速度（书中第101页）
            cmd['g_command'] = self.aircraft.max_instantaneous_g(p['my_speed_ktas'])
            cmd['pitch_rate'] = -5.0 if p['altitude_diff_ft'] > 1000 else 0.0
            cmd['throttle'] = 1.0

        elif self.state == TacticalState.ENERGY_FIGHT:
            # 能量战：持续G转弯，维持速度（书中第106-107页）
            cmd['g_command'] = self.aircraft.max_sustained_g(
                p['my_speed_ktas'], 0  # 简化
            )
            cmd['throttle'] = 1.0

        elif self.state == TacticalState.BREAK_TURN:
            # 急转弯防御：最大G，转向威胁（书中第58页）
            cmd['g_command'] = self.aircraft.max_g
            cmd['roll_rate'] = 60.0   # 快速滚转
            cmd['throttle'] = 1.0
            # 施放干扰
            cmd['deploy_flare'] = True
            cmd['deploy_chaff'] = True

        elif self.state == TacticalState.EXTEND_ESCAPE:
            # 延伸脱离：最大速度直线飞行
            cmd['g_command'] = 1.0
            cmd['throttle'] = 1.0
            # 保持目标在尾部可见范围

        elif self.state == TacticalState.JINK:
            # 急动：每1-2秒改变90°方向（书中第28页）
            t = self.state_timer
            direction = 1 if (t % 2.0) < 1.0 else -1
            cmd['roll_rate'] = direction * 120.0  # 急速滚转
            cmd['g_command'] = self.aircraft.max_g
            cmd['deploy_flare'] = True

        return cmd
```

---

## 6. 拦截几何计算

### 6.1 截击点预测（碰撞航向）

```python
def compute_collision_heading(
    interceptor_pos, interceptor_speed_ktas: float,
    target_pos, target_vel_ktas_vec
) -> tuple[np.ndarray, float]:
    """
    计算碰撞航向（书中第347-349页）
    
    碰撞条件：目标方位角保持恒定
    ATA（天线训练角）≈ TAA（当两机速度接近时）
    
    Returns: (heading_vector, time_to_intercept)
    """
    los = target_pos - interceptor_pos
    los_dist = np.linalg.norm(los)
    los_dir = los / los_dist

    # 目标速度大小
    target_speed = np.linalg.norm(target_vel_ktas_vec)
    interceptor_speed = interceptor_speed_ktas

    # 用正弦定理求碰撞角
    target_dir = target_vel_ktas_vec / target_speed
    sin_angle = (target_speed / interceptor_speed) * \
                np.abs(np.cross(target_dir[:2], los_dir[:2]))
    sin_angle = np.clip(sin_angle, -1, 1)

    lead_angle = np.arcsin(sin_angle)

    # 旋转LOS方向得到碰撞航向
    cos_a = np.cos(lead_angle)
    sin_a = np.sin(lead_angle)
    # 2D旋转矩阵
    rot = np.array([[cos_a, -sin_a], [sin_a, cos_a]])
    heading_2d = rot @ los_dir[:2]
    heading = np.array([heading_2d[0], heading_2d[1], 0])

    # 估算拦截时间
    # 近似：考虑目标移动
    tti = los_dist / (interceptor_speed + target_speed * np.dot(los_dir, target_dir))
    return heading, max(tti, 0.1)

def compute_lateral_separation(
    interceptor_pos, interceptor_vel,
    target_pos, target_vel
) -> float:
    """
    计算侧向间隔（书中第350页公式）
    
    Displacement ≈ 100 × TAA(degrees) × Range(NM)  [ft]
    
    用于尾部转换截击的计划
    """
    taa_deg = compute_TAA(target_pos, target_vel, interceptor_pos)
    range_nm = np.linalg.norm(target_pos - interceptor_pos) / 6076.0  # ft→NM

    return 100.0 * taa_deg * range_nm  # 英尺

def plan_stern_conversion(
    interceptor_pos, interceptor_vel, interceptor_speed_ktas: float,
    target_pos, target_vel, target_speed_ktas: float,
    desired_conversion_range_ft: float = 10000,
    desired_trail_distance_ft: float = 3000
) -> dict:
    """
    尾部转换截击规划（书中第350-353页）
    
    步骤：
    1. 计算需要的侧向间隔
    2. 向外偏转获得间隔
    3. 在转换距离开始转弯
    4. 滚出在目标后方
    """
    current_sep = compute_lateral_separation(
        interceptor_pos, interceptor_vel, target_pos, target_vel
    )
    needed_sep = desired_conversion_range_ft * 0.5  # 经验公式

    # 转换范围（基于拦截机转弯半径）
    turn_radius = interceptor_speed_ktas ** 2 / (9.81 * 4.0 * 1.689 ** 2)  # 约4G转弯

    dtg = compute_DTG(interceptor_vel, target_vel)  # 转到平行所需角度

    return {
        'current_separation_ft': current_sep,
        'needed_separation_ft': needed_sep,
        'need_more_separation': current_sep < needed_sep,
        'conversion_range_ft': desired_conversion_range_ft,
        'estimated_turn_radius_ft': turn_radius,
        'dtg_deg': dtg,
        'action': 'cut_away' if current_sep < needed_sep else 'parallel_and_drive'
    }

def compute_DTG(interceptor_vel, target_vel) -> float:
    """
    DTG（Degrees To Go）：截击机转到平行目标航向所需的角度
    书中第347页
    """
    int_dir = interceptor_vel / np.linalg.norm(interceptor_vel)
    tgt_dir = target_vel / np.linalg.norm(target_vel)
    cos_dtg = np.clip(np.dot(int_dir, tgt_dir), -1, 1)
    return np.degrees(np.arccos(cos_dtg))
```

### 6.2 F-极计算（导弹立足距离）

```python
def compute_f_pole(
    shooter_pos, shooter_vel_ktas: float,
    target_pos, target_vel_ktas: float,
    missile_avg_speed_ktas: float,
    missile_tof: float
) -> float:
    """
    F-极（F-Pole）：导弹命中时射手与目标的距离（书中第51页）
    
    最大F-极：先加速再减速
    用于：SARH导弹（需要持续照射），评估是否被对手导弹先打到
    """
    # 导弹命中位置（简化）
    target_at_impact = np.array(target_pos) + \
                       np.array(target_vel_ktas) * 0.5144 * missile_tof

    # 射手在导弹命中时的位置
    shooter_at_impact = np.array(shooter_pos) + \
                        np.array(shooter_vel_ktas) * 0.5144 * missile_tof

    return np.linalg.norm(target_at_impact - shooter_at_impact) * 3.281  # m→ft

def maximize_f_pole(shooter_speed_ktas: float) -> dict:
    """
    如何最大化F-极（书中第51-52页）：
    1. 以最大速度发射（增大导弹初速）
    2. 发射后减速（让导弹增大相对速度）
    3. 可以小角度转离（增大目标距离）
    """
    return {
        'action': 'fire_at_max_speed_then_decelerate',
        'post_launch_throttle': 0.0,  # 收油
        'post_launch_turn_deg': 15,   # 轻微偏转增大距离
        'note': 'For SARH: must maintain radar lock, limits turn option'
    }
```

---

## 7. 编队战术实现

### 7.1 战斗横队 (Combat Spread)

```python
class FormationManager:
    """编队管理器"""

    COMBAT_SPREAD_SPACING = 1500  # 英尺，约1个转弯半径

    def compute_wingman_position(
        self,
        leader_pos, leader_vel, leader_heading_deg: float,
        side: str = "right",   # "left" | "right"
        spacing_ft: float = 1500
    ) -> np.ndarray:
        """
        计算僚机理想位置（战斗横队）
        书中第241页：线排并排，约1个转弯半径间距
        """
        heading_rad = np.radians(leader_heading_deg)
        forward = np.array([np.cos(heading_rad), np.sin(heading_rad), 0])
        right = np.array([np.sin(heading_rad), -np.cos(heading_rad), 0])

        offset = right if side == "right" else -right
        return leader_pos + offset * spacing_ft * 0.3048  # ft→m

    def compute_tac_turn(
        self,
        leader_pos, leader_vel, leader_heading_deg: float,
        wingman_pos, wingman_vel,
        turn_direction: str = "left",
        turn_deg: float = 90.0
    ) -> dict:
        """
        战术转弯（Tac Turn / Cross-Over Turn）
        书中第249-251页
        
        步骤：
        1. 长机立即开始转弯
        2. 僚机延迟2-4秒后转弯
        3. 僚机轻微跨越长机飞行路径
        4. 两机在新航向上重新并排
        
        优势：整个过程保持良好目视掩护
        """
        return {
            'leader_action': {
                'turn_immediately': True,
                'turn_direction': turn_direction,
                'turn_rate_dps': 12.0
            },
            'wingman_action': {
                'delay_seconds': 3.0,  # 关键：延迟让两机错开
                'turn_direction': turn_direction,
                'cross_under': True,   # 从长机下方穿过
                'turn_rate_dps': 15.0  # 略快补偿延迟
            },
            'estimated_completion': turn_deg / 12.0 + 3.0  # 秒
        }

    def bracket_attack(
        self,
        section_pos_left, section_vel_left,
        section_pos_right, section_vel_right,
        bogey_section_pos, bogey_section_vel
    ) -> dict:
        """
        钳制攻击（Bracket）（书中第241-243页）
        两机分从两侧绕过敌方编队两翼
        
        最优：无论敌机转向哪里都有一机占优
        """
        # 判断从哪侧攻击哪个目标
        bogey_span = np.linalg.norm(
            bogey_section_pos[1] - bogey_section_pos[0]
        ) * 3.281 if len(bogey_section_pos) > 1 else 3000.0

        return {
            'left_fighter_target': 'bogey_far_side',     # 交叉攻击对面目标
            'right_fighter_target': 'bogey_near_side',
            'left_turn_deg': 30,   # 向外偏转获得包围位置
            'right_turn_deg': 30,
            'altitude_split': True,        # 一高一低增加三维包围
            'altitude_split_ft': 2000,
            'timing': 'simultaneous',      # 同时到达
            'midair_collision_risk': bogey_span < 2000   # 近距注意碰撞
        }
```

### 7.2 双重攻击与松散双机

```python
class TwoVsOneController:
    """2v1 战术控制器（书中第5章）"""

    def update_double_attack(
        self,
        engaged_fighter: dict,   # 进攻机状态
        free_fighter: dict,      # 自由机状态
        bogey: dict              # 目标状态
    ) -> tuple[dict, dict]:
        """
        双重攻击战术更新
        书中第200-214页
        
        进攻机：机动攻击目标
        自由机：防止目标攻击进攻机，时机成熟时接管攻击
        """
        # 判断是否需要角色切换
        engaged_threatened = self._is_threatened(engaged_fighter, bogey)
        bogey_in_free_range = self._in_weapons_range(free_fighter, bogey)

        engaged_cmd = {}
        free_cmd = {}

        if engaged_threatened:
            # 进攻机受威胁：自由机立即介入
            free_cmd['attack_bogey'] = True
            free_cmd['priority'] = 'relieve_engaged'
            engaged_cmd['defend'] = True
        elif bogey_in_free_range and self._engaged_has_advantage(engaged_fighter, bogey):
            # 目标在自由机射程内且进攻机占优：保持施压
            engaged_cmd['continue_press'] = True
            free_cmd['position_for_shot'] = True
        else:
            # 正常：进攻机攻击，自由机覆盖
            engaged_cmd['attack'] = True
            free_cmd['cover_engaged'] = True
            free_cmd['watch_bogey'] = True

        return engaged_cmd, free_cmd

    def sandwich_maneuver(
        self,
        attacker_pos, attacker_vel,
        support_pos, support_vel,
        bogey_pos, bogey_vel
    ) -> dict:
        """
        三明治机动（书中第214-215页）
        目标被前后包夹
        """
        # 攻击机在目标后方，支援机在前方
        attacker_los = bogey_pos - attacker_pos
        support_los = bogey_pos - support_pos

        attacker_ahead = np.dot(
            attacker_vel / np.linalg.norm(attacker_vel),
            attacker_los / np.linalg.norm(attacker_los)
        )

        if attacker_ahead > 0.7:  # 攻击机在追目标
            return {
                'attacker_action': 'press_from_rear',
                'support_action': 'position_forward_quarter',
                'coordination': 'support_fires_if_bogey_turns_away'
            }
        else:
            return {
                'attacker_action': 'bracket_from_side',
                'support_action': 'maintain_rear_threat',
                'coordination': 'both_press_simultaneously'
            }

    def drag_tactic(
        self,
        dragger_pos, dragger_vel,
        shooter_pos, shooter_vel,
        bogey_pos, bogey_vel
    ) -> dict:
        """
        拖饵战术（书中第244-246页）
        一机诱敌追击，另一机从侧面截击追击者
        """
        # 拖饵机应：减速、给目标侧面暴露、在射手的射线上诱目标
        dragger_range = np.linalg.norm(bogey_pos - dragger_pos)
        shooter_range = np.linalg.norm(bogey_pos - shooter_pos)

        return {
            'dragger_action': {
                'type': 'fly_slowly_draw_enemy',
                'speed_reduction': 0.85,    # 减速到最大速度的85%
                'heading': 'maintain_ahead_of_enemy',
                'max_time': 15.0,           # 秒，不能被诱太久（书中提示）
            },
            'shooter_action': {
                'type': 'flank_attack',
                'target': 'bogey_when_focused_on_dragger',
                'optimal_bearing': 90,      # 目标侧面最佳
            },
            'abort_condition': 'bogey_ignores_dragger',  # 目标不上钩时中止
            'risk': 'dragger_exposed_if_shooter_fails'
        }
```

---

## 8. 感知系统

### 8.1 视觉检测模型

```python
class VisualDetectionSystem:
    """
    目视检测系统
    基于 Shaw 第10章"目视注意事项"（第374-383页）
    """

    def compute_visual_range(
        self,
        target_size_ft: float,         # 目标尺寸（翼展等）
        background_contrast: float,    # 0=完美伪装，1=完全暴露
        visibility_nm: float,          # 能见度
        is_scanning: bool = True       # 扫描模式还是固定盯
    ) -> float:
        """
        基础目视发现距离（书中第378-383页）
        
        关键规律（书中）：
        - 约90%的被击落者在中弹前不知道被攻击
        - 亮色目标可在10英里外被发现
        - 暗色伪装可将发现距离缩短到2-3英里
        - 相对运动是外围视觉的主要触发因素
        """
        base_range_nm = target_size_ft / 60.0  # 粗略基础（英尺/弧分）

        # 伪装效果（书中第381-382页）
        camo_factor = 0.3 + 0.7 * background_contrast

        # 扫描vs盯视（书中第379页：主动扫描更有利于防御发现）
        scan_factor = 1.5 if is_scanning else 0.7

        # 能见度限制
        max_range = min(visibility_nm, base_range_nm * camo_factor * scan_factor)
        return max_range

    def compute_blind_cone(
        self,
        aircraft_type: str = "typical"
    ) -> dict:
        """
        飞机盲区（书中第374页）
        约90%的损失来自未被发现的攻击（书中）
        """
        # 典型盲区（后下方最盲）
        return {
            'dead_six': 10,          # 正后方盲角范围（度）
            'low_six': 20,           # 正后下方盲角
            'belly': 15,             # 腹部盲区（需要滚转才能看到）
            'scan_interval_sec': 5.0 # 应每5秒扫描一次盲区
        }

    def is_in_sun_blind_zone(
        self,
        observer_pos, target_pos, sun_direction
    ) -> bool:
        """目标是否在太阳方向（在逆光区）"""
        to_target = target_pos - observer_pos
        to_target /= np.linalg.norm(to_target)
        sun_dir = sun_direction / np.linalg.norm(sun_direction)

        angle = np.degrees(np.arccos(np.clip(np.dot(to_target, sun_dir), -1, 1)))
        return angle < 15  # 书中：太阳附近15°内的目标几乎不可见

    def detect_missile_launch(
        self,
        missile_has_smoke: bool,
        launch_range_ft: float,
        visibility_nm: float
    ) -> tuple[bool, float]:
        """
        能否目视发现导弹发射（书中第60-61页）
        
        "烟雾发动机在某些条件下20-30英里外可见"（书中）
        无烟发动机几乎不可能早期发现
        """
        if not missile_has_smoke:
            # 无烟：只能靠RWR或拖尾气
            detection_range_ft = min(
                3000,  # 只有非常近才能看到气动光迹
                launch_range_ft
            )
        else:
            # 有烟：显著可见
            detection_range_ft = min(
                visibility_nm * 6076 * 0.5,  # 能见度一半处
                launch_range_ft
            )

        detected = launch_range_ft <= detection_range_ft
        time_to_impact_estimate = None
        if detected:
            avg_missile_fps = 2000
            time_to_impact_estimate = launch_range_ft / avg_missile_fps

        return detected, time_to_impact_estimate
```

### 8.2 雷达系统模型

```python
class RadarSystem:
    """
    机载雷达系统（书中第40-46页）
    """

    def __init__(self, params: dict):
        self.radar_type     = params['type']  # 'pulse' | 'pd' | 'cw'
        self.max_range_ft   = params['max_range']
        self.beam_width_deg = params['beam_width']
        self.lookdown_cap   = params.get('lookdown', False)  # 多普勒雷达
        self.gimbal_lim_deg = params.get('gimbal_limit', 60)

    def compute_detection_range(
        self,
        target_rcs: float,    # 目标雷达截面积（m²）
        altitude_ft: float,   # 雷达平台高度
        look_down_angle: float,  # 向下观测角
        target_taa: float     # 目标纵横角（用于多普勒限制）
    ) -> float:
        """
        雷达探测距离（书中第41-43页）
        
        多普勒雷达限制：
        - 横向目标（约90° TAA）= 地波干扰最严重
        - 尾随目标（约180° TAA）= 多普勒频移接近零，难以区分
        - 正面目标（约0° TAA） = 多普勒优势最大，可俯视探测
        """
        # 基础探测距离（依赖目标RCS的1/4次方）
        base_range = self.max_range_ft * (target_rcs / 10.0) ** 0.25

        # 俯视杂波衰减（书中第43页）
        if not self.lookdown_cap:
            if look_down_angle > 5:
                # 非多普勒雷达在俯视时严重衰减
                attenuation = 1.0 - (look_down_angle - 5) / 30.0
                base_range *= max(0.2, attenuation)

        # 多普勒雷达：横侧死区（书中第43页）
        if self.radar_type == 'pd':
            # 横向目标几乎无法探测（关闭速度接近零）
            if 70 < target_taa < 110:
                beam_doppler_factor = 0.1  # 严重衰减
            elif 160 < target_taa < 180:
                # 尾随目标：侧瓣干扰
                beam_doppler_factor = 0.6
            else:
                beam_doppler_factor = 1.0
            base_range *= beam_doppler_factor

        return min(base_range, self.max_range_ft)

    def can_track_target(
        self,
        target_los_angle_deg: float,  # 目标相对雷达视轴的角度
        target_los_rate_dps: float    # 目标LOS角速率
    ) -> tuple[bool, str]:
        """
        雷达能否跟踪目标（书中第43-44页）
        
        两个限制：
        1. 陀螺追踪速率限制
        2. 万向锁限制（导引头碰到物理止档）
        """
        # 万向锁限制
        if abs(target_los_angle_deg) > self.gimbal_lim_deg:
            return False, "gimbal_limit"

        # 追踪速率限制（书中第43页）
        max_tracking_rate = 30.0  # 典型值 deg/s
        if abs(target_los_rate_dps) > max_tracking_rate:
            return False, "tracking_rate_exceeded"

        return True, "tracking"
```

---

## 9. 数据结构参考

### 9.1 战术态势结构体

```python
from dataclasses import dataclass, field
from typing import Optional, List

@dataclass
class FighterState:
    """单架飞机完整战术状态"""
    # 运动学
    pos: np.ndarray         # [x, y, z] 米
    vel: np.ndarray         # [vx, vy, vz] m/s
    speed_ktas: float       # 真空速（节）
    speed_kias: float       # 表速（节）
    altitude_ft: float      # 高度（英尺）
    heading_deg: float      # 航向（度）
    pitch_deg: float        # 俯仰角
    roll_deg: float         # 滚转角
    current_g: float        # 当前G载荷

    # 能量状态
    energy_ft: float        # 比能量 Es
    ps_fps: float           # 比剩余功率

    # 武器系统
    gun_ammo: int           # 剩余炮弹数
    missile_count: int      # 剩余导弹数
    radar_locked_id: Optional[str] = None

    # 战术态势
    tactical_state: TacticalState = TacticalState.INTERCEPT
    threat_warning: bool = False
    missile_toi: float = 99.0  # 导弹命中倒计时（秒）


@dataclass
class EngagementSituation:
    """完整交战态势（传递给AI）"""
    self_state: FighterState
    target_state: FighterState

    # 计算参数（预计算以提高效率）
    range_ft: float = 0.0
    aot_deg: float = 0.0
    aon_deg: float = 0.0
    tca_deg: float = 0.0
    los_rate_dps: float = 0.0
    closure_fps: float = 0.0
    separation_ft: float = 0.0
    energy_advantage_ft: float = 0.0

    # 武器评估
    gun_probability: float = 0.0
    best_missile_range_pct: float = 0.0  # 当前距离/最大射程

    # 威胁评估
    incoming_missile: bool = False
    missile_toi: float = 99.0

    def update(self):
        """更新所有计算参数"""
        self.range_ft = np.linalg.norm(
            self.target_state.pos - self.self_state.pos
        ) * 3.281
        self.aot_deg = compute_AOT(
            self.target_state.pos, self.target_state.vel,
            self.self_state.pos
        )
        # ... 其他参数
```

---

## 10. 数值参数速查表

### 10.1 几何阈值

| 参数 | 值 | 含义 | 来源 |
|------|-----|------|------|
| 机炮最优AOT | 30°–60° | LCOS跟踪最佳区 | Shaw Ch.1 |
| 机炮固定瞄准AOT | 0°–30° | 固定瞄准镜最佳 | Shaw Ch.1 |
| 高大摆触发AOT | 20°–70° | 适合执行高大摆 | Shaw Ch.2 |
| 领先转弯优势间隔 | < 2×转弯半径 | 超过此值几乎无效 | Shaw Ch.2 |
| 剪刀战翻转量 | 60°–90° | 每次有效翻转 | Shaw Ch.2 |
| 导弹前/后象限比 | ~5:1 | 前象限射程优势 | Shaw Ch.1 |

### 10.2 武器参数（典型现代战斗机）

| 武器类型 | 最大射程 | 最小射程 | 最优AOT | G需求 |
|---------|---------|---------|---------|------|
| 机炮 (M61) | 900m (3000ft) | 150m (500ft) | 0°–60° | <6G |
| RQ红外 (AIM-9B类) | 3km | 300m | 150°–180° | <4G发射 |
| 全向红外 (AIM-9L类) | 3–5km (后) / 5km (前) | 300m | 任意 | <5G |
| SARH (AIM-7类) | 5–20km | 1km | 任意 | 需持续照射 |
| ARH (AIM-120类) | 10–50km | 500m | 任意 | 发射后不管 |

### 10.3 飞行性能典型值

| 参数 | 现代轻型战斗机 | 现代重型战斗机 |
|------|------------|------------|
| 最大G | 9G | 7–9G |
| 拐角速度 (KIAS) | 400–450 | 450–550 |
| 失速速度 (KIAS) | 120–140 | 130–160 |
| 持续转弯速率 | 14–18 °/s | 10–15 °/s |
| 最大瞬时转弯速率 | 20–28 °/s | 16–22 °/s |
| 最小转弯半径 | 900–1200m | 1200–1800m |
| 推重比 | 1.0–1.2 | 0.8–1.1 |
| 翼载荷 (lb/ft²) | 50–70 | 80–120 |

### 10.4 战术时间常数

| 场景 | 时间 | 备注 |
|------|------|------|
| 机炮跟踪稳定时间 | 0.5–1.5秒 | LCOS准镜安定时间 |
| 子弹飞行时间 (1000ft) | 0.3–0.5秒 | 取决于射手速度 |
| 快照持续时间 | 0.1–0.5秒 | 准星扫过目标的时间 |
| 导弹引信武装时间 | 0.3–1.5秒 | 决定最小射程 |
| 导弹制导锁定时间 | 0.5–2秒 | 伺服马达安定时间 |
| 急动间隔建议 | 1–2秒 | 每次方向改变 |
| 曳光弹有效持续 | 2–4秒 | 每枚曳光弹 |
| 高大摆全程时间 | 6–12秒 | 取决于速度/高度 |

### 10.5 高度对导弹射程的倍数（书中图1-10）

| 高度 | 射程倍数（相对海平面） |
|------|-----------------|
| 海平面 | 1.0× |
| 10,000 ft | 1.5× |
| 20,000 ft | 2.0× |
| 30,000 ft | 3.0× |
| 40,000 ft | 4.0× |

---

## 附录：关键书中原则到代码的映射

| 书中原则 | 实现位置 | 关键变量 |
|---------|---------|---------|
| "约90%损失来自未被发现的攻击" | `VisualDetectionSystem` | `blind_cone`, `detection_range` |
| "导弹需要约5倍目标G" | `MissileSystem.can_evade()` | `missile_g_required = target_g * 5` |
| "前象限射程约为后象限5倍" | `MissileSystem.compute_max_range()` | `max_range_fq / max_range_rq ≈ 5` |
| "拐角速度是最优机动速度" | `AircraftPerformance` | `optimal_corner_speed()` |
| "角度战用鼻对鼻，能量战用鼻对尾" | `FighterAI._choose_offensive_tactic()` | `TacticalState` 选择 |
| "飞行路径间隔决定领先转弯收益" | `compute_lead_turn_opportunity()` | `separation_ft vs turn_radius` |
| "高大摆：用高度换角度" | `HighYoYo.compute_control_command()` | `phase: climb → roll → dive` |
| "比例导引消除LOS漂移" | `MissileSystem.proportional_navigation_command()` | `nav_constant = 3-5` |
| "急动方向每次变90°以上" | `FighterAI._execute_state(JINK)` | `roll_rate direction alternates` |
| "高度40000ft射程约为海平面4倍" | `compute_max_range()` | `altitude_factor` 计算 |

---

*基于 Robert L. Shaw《Fighter Combat: Tactics and Maneuvering》(1985, Naval Institute Press)*  
*本文档为 AGL 项目内部开发参考，包含工程化的物理模型和算法伪代码*
