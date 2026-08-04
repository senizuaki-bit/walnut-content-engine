# 第三方参考与素材边界

本 Demo 的新增实现采用 clean-room 方式：只研究公开项目的玩法流程、交互模式与工程分层，没有复制下列仓库的源码、地图、角色、美术、音频或原作名称。

| 参考项目 | 核验结果 | 本项目处理 |
| --- | --- | --- |
| [GAMECREATOR1010/Final-Knight-](https://github.com/GAMECREATOR1010/Final-Knight-) | 代码标注 Apache-2.0；README 同时说明《元气骑士》原版素材归原作者且仅供学习 | 仅参考“安全屋—战斗—传送门”概念，不复制代码或素材 |
| [CalvinWan0101/soul-knight](https://github.com/CalvinWan0101/soul-knight) | 未发现明确许可证 | 仅参考统一交互与技能冷却概念 |
| [MountPOTATO/SoulKnight](https://github.com/MountPOTATO/SoulKnight) | 未发现明确许可证 | 仅参考逻辑/资源分层概念 |
| [Wizard23333/SoulKnightTeamProject](https://github.com/Wizard23333/SoulKnightTeamProject) | 未发现明确许可证，且包含原作风格素材 | 仅参考 Actor / Scene / Props 与固定房间概念 |
| [beohoang98/soul_knight_clone](https://github.com/beohoang98/soul_knight_clone) | 未发现明确许可证 | 不复制源码或 Assets |
| [peler-little-pig/PelerGame](https://github.com/peler-little-pig/PelerGame) | GPL 标注版本不清，且 README 提及由 Minecraft 图片修改的素材 | 仅参考数据驱动生命周期概念 |

## 发布前资产审计

本次新增家园、战斗与教学逻辑复用了仓库中已有的 Godot 素材。由于仓库目前没有完整的资产来源台账，公开发布、参赛打包或商业使用前，项目负责人仍需逐项确认 my_topdown_game-main/assets/ 与 my_topdown_game-main/content/skins/ 中素材的作者、来源 URL、许可证、修改情况和署名要求。来源不明的素材应替换为原创或许可明确的资产。

GitHub 对“无许可证公开仓库”的说明见 [Licensing a repository](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/licensing-a-repository)。
