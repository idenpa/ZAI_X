本版本为开源漫画客户端《再漫画X》的衍生优化版。源码基于Fusn126/[链接](https://github.com/Fusn126/ZAI_X)] 的二次开发分支，并溯源致敬 [xiaoyaocz/[链接](https://github.com/xiaoyaocz/flutter_dmzj)] 的早期开源工作。
提供iOS,Android,Winows,macOS版本和对应版本的workflow配置。<br />
主要改动：<br />
源码修复：清理了上游代码中遗留的本地环境配置（如本地代理、缺失的 Kotlin 插件），确保云端环境能纯净构建。<br />
CI/CD 搭建：补齐了原作者未提供的 iOS、macOS 和 Windows 自动化云端构建流程。<br />
桌面端 (macOS & Windows) 专属优化：窗口大小记忆；初始尺寸优化；交互适配。


下面是原来的readme：

---

<p align="center">
    <img width="128" src="/document/logo.png" alt="DMZJX logo">
</p>
<h2 align="center">ZAI-X</h2>

<p align="center">
使用Flutter编写的再漫画跨平台第三方客户端
</p>

![浅色模式](/document/screenshot_light.jpg)

![深色模式](/document/screenshot_dark.jpg)

## 支持平台

- [x] Android
- [x] iOS
- [x] Windows `Beta`
- [x] MacOS `Beta`
- [x] Linux `Beta`

请到[Releases](https://github.com/xiaoyaocz/flutter_dmzj/releases)下载最新版本，iOS请下载ipa文件自行签名安装。

反馈问题、相关讨论请到[Discussions](https://github.com/xiaoyaocz/flutter_dmzj/discussions)，代码改进请直接提交PR。

## 声明

- 本项目为[再漫画](https://zaimanhua.com)第三方开源APP

- 本项目仅用于学习交流编程技术，严禁将本项目用于商业目的。如有任何商业行为，均与本项目无关。

- 本项目内所有资源版权均归属于其著作者或动漫之家所有

- 如果本项目存在侵犯您的相关权益的情况，请及时与开发者联系，开发者将会及时删除有关内容。

## License

[GPL-3.0 License](https://github.com/xiaoyaocz/flutter_dmzj/blob/main/LICENSE)，禁止用于任何商业用途
