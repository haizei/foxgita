# Gita 谱页识别服务

服务接收 JPEG/PNG 谱页，调用运营方配置的 OpenAI-compatible 视觉模型，返回待校正音乐 JSON。PDF 在 iPhone 上分页渲染。没有音频接口，不接收弹奏声音。客户端明确确认上传后才提交页面。

## 本地启动

使用 Python 3.11+，在独立环境安装 `requirements.txt`。通过运行环境或密钥管理器提供以下变量，勿提交密钥：

| 变量 | 用途 |
| --- | --- |
| `GITA_OMR_BASE_URL` | 视觉模型 HTTPS API base，通常含 `/v1` |
| `GITA_OMR_MODEL` | 支持图像输入的实际模型 ID |
| `GITA_OMR_API_KEY` | 服务端模型密钥 |
| `GITA_SERVICE_TOKENS_JSON` | 产品会话令牌到稳定用户主体的 JSON 映射，由运营方预置；例如 `{"<随机会话令牌>":"<用户主体>"}` |
| `GITA_OMR_DATABASE` | SQLite 文件路径，默认工作目录 `jobs.sqlite` |
| `PORT` | 回环监听端口，默认 8788 |

运行 `python3 score-service/service.py`。服务只绑定 `127.0.0.1`；正式部署必须置于提供 HTTPS、请求体限制和访问控制的反向代理后。不能把调试令牌或模型密钥嵌入 App。

iOS 正式版通过构建配置提供 `GitaScoreServiceURL`，产品会话令牌由宿主登录系统写入独立 Keychain service `com.haizei.foxgita.score-service`。当前工程没有产品账户令牌发行器，本服务不伪造登录系统；部署和账户接入仍需落实。DEBUG 无产品服务 URL 时，可按用户授权读取该 iPhone 已有的 Gita 模型设置；不会导出原有密钥。

## 接口与生命周期

所有请求必须有 `Authorization: Bearer <产品会话令牌>`。

- `POST /v1/recognitions`：`Idempotency-Key` + `{"pages":["<base64 JPEG/PNG>"]}`，202 返回任务 UUID。
- `GET /v1/recognitions/<UUID>`：queued/running/succeeded/failed/cancelled，含逐页状态；成功时附 `draft`。警告和音符保留原始页码，可提供规范化区域框供校正界面定位。
- `DELETE /v1/recognitions/<UUID>`：取消并清除合并结果；迟到的模型结果不能恢复任务。排队任务立即释放容量，进行中的模型请求最多运行到总时限。已完成的页级音乐草稿暂存至任务过期，用于重试时跳过成功页；服务器不保留原图。

最多20页、解码后30MB，HTTP体40.1MB，单页40MP；最多8个进行中任务、2个模型 worker、32个连接。单次页级模型调用有240秒进程级总时限，含连接、响应和格式回退。任务属于稳定用户主体，其他主体不可读或取消。相同 key 与内容的重试复用任务；失败/取消可重试，只重新调用未成功页，内容变化返回409。客户端重试会重新提交整组页字节进行一致性校验，成功页不再次计费调用。未完成任务在服务重启后转为失败。结果在24小时后于下一次访问时过期清理；生产存储需要定期清理/备份保留策略。谱页只在有界 worker 内存中使用，不写入服务器磁盘；iPhone 保留原件和校正草稿供恢复。

## 验证

`PYTHONPATH=score-service python3 -m unittest discover -s score-service/tests`

从仓库根目录运行以下命令可启动 iOS 模拟器用的离线 HTTP 夹具。将 DEBUG 客户端的服务地址设置为 `http://127.0.0.1:18788`，测试会话令牌为 `fixture-session`。

```sh
PYTHONPATH=score-service python3 -u score-service/tests/fixture_server.py
```

夹具复用正式 HTTP 处理和 SQLite 任务队列。测试服务商对每页延迟 12 秒后返回同一份两小节 TAB 草稿《Fixture Score》，速度 68 BPM。标准输出按行记录请求方法、任务 ID、任务和页状态，以及每次服务商调用的序号和页数。可在收到 running 状态后重启客户端，比较重启前后的任务 ID 与服务商调用数。按 Ctrl-C 结束并清理临时数据库。

测试覆盖实际 HTTP 协议与模拟服务商响应，不代表模型识谱准确率。需要使用实际配置分别验证印刷 TAB、五线谱、清晰照片，并对照音符、节奏与小节结构；不得以测试夹具作为识谱效果交付。
