# AGL — 项目概述

Godot 4.6 项目，GDScript，GL Compatibility 渲染器。

俯视视角的战斗机模拟沙盒。玩家以 RTS 方式操控战斗机（点击地图位置，飞机自主转弯飞向目标），飞机遵循较真实的航空物理。2D 场景 + 虚拟高度（高度仅作为数值存在，通过图标缩放可视化）。

## 目录结构

```
scenes/
  main.tscn              主场景（入口）
  aircraft.tscn           飞机场景模板
scripts/
  main.gd                主场景：相机控制、鼠标输入、网格背景
  aircraft.gd            飞机：物理模型 + 线框绘制 + 虚线航向指示
  aircraft_params.gd     AircraftParams Resource，所有飞机性能参数
  ai_controller.gd       简单巡逻 AI（航路点循环）
  hud.gd                 HUD：左上角显示选中飞机数据
resources/
  default_fighter.tres    F-16 参数（友方，绿色）
  enemy_fighter.tres      MiG-29 参数（敌方，红色）
docs/
  project-overview.md     本文件
  features.md             已实现功能详述
  architecture.md         架构设计与扩展规划
  aircraft-params.md      飞机参数说明
```

## 场景树结构（main.tscn）

```
Main (Node2D, main.gd)
├── Camera2D
├── PlayerAircraft (Aircraft, team=0, default_fighter.tres)
├── EnemyAircraft1 (Aircraft, team=1, enemy_fighter.tres)
│   └── AIController1 (AIController, patrol_altitude=6000)
├── EnemyAircraft2 (Aircraft, team=1, enemy_fighter.tres)
│   └── AIController2 (AIController, patrol_altitude=4500)
└── HUD (CanvasLayer, hud.gd)
    └── InfoLabel (Label)
```
