# pg_setup 配置文件格式说明

本文档详细说明 pg_setup 配置文件的格式和所有可用的配置选项。

## 基本格式

配置文件使用简单的 `key=value` 格式：

```ini
# 这是注释
key=value
another_key=another_value
```

### 格式规则

1. **注释**：以 `#` 开头的行被视为注释
2. **空行**：空行会被忽略
3. **键值对**：使用 `=` 分隔键和值
4. **空格**：键和值周围的空格会被自动去除
5. **大小写**：键名不区分大小写
6. **引号**：值不需要引号（除非值本身包含引号）

### 示例

```ini
# 正确的格式
data_directory=/var/lib/postgresql/data
encoding=UTF8
port=5432

# 也是正确的（空格会被去除）
listen_addresses = localhost
username = postgres

# 错误的格式
data_directory /var/lib/postgresql/data  # 缺少 =
=value  # 缺少键
key=  # 值为空（某些键允许）
```

---

## 配置选项详解

### 数据目录

#### data_directory

**说明**：PostgreSQL 数据库集群的数据目录路径

**类型**：字符串（路径）

**默认值**：无（必须指定）

**示例**：
```ini
data_directory=/var/lib/postgresql/data
data_directory=~/pgdata
data_directory=/home/user/postgresql/16/data
```

**注意事项**：
- 目录必须为空或不存在
- 路径可以是绝对路径或相对路径
- 支持 `~` 表示用户主目录
- 目录将被创建并设置权限为 0700

---

### 字符编码和区域设置

#### encoding

**说明**：新数据库的默认字符编码

**类型**：字符串

**默认值**：UTF8

**有效值**：
- UTF8（推荐）
- SQL_ASCII
- LATIN1
- EUC_JP
- EUC_CN
- EUC_KR
- EUC_TW
- ISO_8859_5
- ISO_8859_6
- ISO_8859_7
- ISO_8859_8
- 等等

**示例**：
```ini
encoding=UTF8
encoding=LATIN1
```

#### locale

**说明**：新数据库的默认区域设置

**类型**：字符串

**默认值**：系统当前区域设置

**示例**：
```ini
locale=en_US.UTF-8
locale=zh_CN.UTF-8
locale=C
locale=POSIX
```

**注意事项**：
- 区域设置必须在系统中已安装
- 使用 `locale -a` 查看可用的区域设置
- `C` 和 `POSIX` 是特殊的区域设置，提供最小功能

#### lc_collate

**说明**：字符串排序规则

**类型**：字符串

**默认值**：与 `locale` 相同

**示例**：
```ini
lc_collate=en_US.UTF-8
lc_collate=C
```

#### lc_ctype

**说明**：字符分类（大小写、数字等）

**类型**：字符串

**默认值**：与 `locale` 相同

**示例**：
```ini
lc_ctype=en_US.UTF-8
lc_ctype=C
```

---

### 超级用户配置

#### superuser

**说明**：数据库超级用户名

**类型**：字符串

**默认值**：当前操作系统用户名

**示例**：
```ini
superuser=postgres
superuser=admin
superuser=dbadmin
```

**注意事项**：
- 用户名必须以字母开头
- 只能包含字母、数字和下划线
- 长度限制为 63 个字符

#### password

**说明**：超级用户密码

**类型**：字符串

**默认值**：无（留空表示无密码）

**示例**：
```ini
password=MySecurePassword123
password=
```

**安全警告**：
- 不推荐在配置文件中存储明文密码
- 建议使用 `pwfile` 选项
- 如果使用此选项，确保配置文件权限为 0600

#### pwfile

**说明**：包含超级用户密码的文件路径

**类型**：字符串（路径）

**默认值**：无

**示例**：
```ini
pwfile=/etc/postgresql/pgpass
pwfile=~/.pgpass
```

**注意事项**：
- 文件应只包含一行密码
- 文件权限应为 0600
- 优先于 `password` 选项

---

### 网络配置

#### listen_addresses

**说明**：服务器监听的 IP 地址

**类型**：字符串

**默认值**：localhost

**有效值**：
- `localhost` - 仅本地连接
- `*` - 所有网络接口
- `0.0.0.0` - 所有 IPv4 接口
- `::` - 所有 IPv6 接口
- 特定 IP 地址（如 `192.168.1.100`）
- 多个地址用逗号分隔

**示例**：
```ini
listen_addresses=localhost
listen_addresses=*
listen_addresses=192.168.1.100
listen_addresses=localhost,192.168.1.100
```

**安全警告**：
- 使用 `*` 或 `0.0.0.0` 会显示安全警告
- 生产环境应限制监听地址

#### port

**说明**：服务器监听的端口号

**类型**：整数

**默认值**：5432

**有效范围**：1024-65535

**示例**：
```ini
port=5432
port=5433
port=15432
```

**注意事项**：
- 端口必须未被占用
- 小于 1024 的端口需要 root 权限（不推荐）

#### max_connections

**说明**：最大并发连接数

**类型**：整数

**默认值**：100

**示例**：
```ini
max_connections=100
max_connections=200
max_connections=20
```

**注意事项**：
- 影响内存使用
- 开发环境可以使用较小值（20-50）
- 生产环境根据需求设置（100-200）

---

### 认证配置

#### auth_method

**说明**：默认认证方式（用于本地和主机连接）

**类型**：字符串

**默认值**：scram-sha-256

**有效值**：
- `trust` - 无密码认证（不安全）
- `scram-sha-256` - SCRAM-SHA-256 加密认证（推荐）
- `md5` - MD5 密码认证（不推荐）
- `password` - 明文密码认证（不安全）
- `peer` - 操作系统用户认证（仅本地）
- `ident` - Ident 协议认证

**示例**：
```ini
auth_method=scram-sha-256
auth_method=trust
auth_method=peer
```

**安全建议**：
- 生产环境使用 `scram-sha-256`
- 开发环境可以使用 `trust`
- 避免使用 `md5` 和 `password`

#### auth_host

**说明**：TCP/IP 连接的认证方式

**类型**：字符串

**默认值**：与 `auth_method` 相同

**示例**：
```ini
auth_host=scram-sha-256
auth_host=md5
```

**注意事项**：
- 覆盖 `auth_method` 对主机连接的设置
- 适用于通过 TCP/IP 的连接

#### auth_local

**说明**：本地 Unix 套接字连接的认证方式

**类型**：字符串

**默认值**：与 `auth_method` 相同

**示例**：
```ini
auth_local=peer
auth_local=trust
```

**注意事项**：
- 覆盖 `auth_method` 对本地连接的设置
- `peer` 仅适用于本地连接

---

### 配置模板

#### profile

**说明**：使用预定义的配置模板

**类型**：字符串

**默认值**：无

**有效值**：
- `development` - 开发模式
- `production` - 生产模式
- `test` - 测试模式

**示例**：
```ini
profile=development
profile=production
profile=test
```

**模板详情**：

**development（开发模式）**：
```ini
# 等效配置
auth_method=trust
max_connections=20
start_server=yes
```

**production（生产模式）**：
```ini
# 等效配置
auth_method=scram-sha-256
max_connections=100
start_server=no
```

**test（测试模式）**：
```ini
# 等效配置
locale=C
port=5433
max_connections=10
auth_method=trust
start_server=yes
```

**注意事项**：
- 配置文件中的其他选项会覆盖模板的默认值
- 命令行参数优先级最高

---

### 服务器控制

#### start_server

**说明**：初始化完成后是否自动启动服务器

**类型**：布尔值

**默认值**：yes

**有效值**：
- `yes`, `true`, `on`, `1` - 启动服务器
- `no`, `false`, `off`, `0` - 不启动服务器

**示例**：
```ini
start_server=yes
start_server=no
start_server=true
start_server=false
```

---

## 完整配置文件示例

### 开发环境配置

```ini
# pg_setup 开发环境配置

# 数据目录
data_directory=~/pgdata

# 字符编码
encoding=UTF8
locale=en_US.UTF-8

# 超级用户
superuser=postgres
# 开发环境可以不设置密码

# 网络配置
listen_addresses=localhost
port=5432
max_connections=20

# 认证（开发环境使用 trust）
auth_method=trust

# 自动启动
start_server=yes
```

### 生产环境配置

```ini
# pg_setup 生产环境配置

# 数据目录
data_directory=/var/lib/postgresql/data

# 字符编码
encoding=UTF8
locale=en_US.UTF-8

# 超级用户
superuser=postgres
pwfile=/etc/postgresql/pgpass

# 网络配置
listen_addresses=localhost
port=5432
max_connections=100

# 认证（生产环境使用安全认证）
auth_method=scram-sha-256

# 不自动启动（手动启动以便检查）
start_server=no
```

### 测试环境配置

```ini
# pg_setup 测试环境配置

# 数据目录
data_directory=/tmp/testdb

# 字符编码（使用 C locale 确保一致性）
encoding=UTF8
locale=C

# 超级用户
superuser=testuser

# 网络配置（使用不同端口避免冲突）
listen_addresses=localhost
port=5433
max_connections=10

# 认证
auth_method=trust

# 自动启动
start_server=yes
```

### 使用模板的简化配置

```ini
# 使用 production 模板
profile=production

# 只需覆盖特定选项
data_directory=/var/lib/postgresql/data
superuser=postgres
pwfile=/etc/postgresql/pgpass
```

---

## 配置优先级

配置选项的优先级（从高到低）：

1. **命令行参数** - 最高优先级
2. **配置文件** - 中等优先级
3. **配置模板** - 较低优先级
4. **默认值** - 最低优先级

### 示例

如果同时使用：
```bash
pg_setup -c myconfig.conf -p 5433 -P development
```

配置文件 `myconfig.conf`：
```ini
port=5432
profile=production
```

最终结果：
- `port=5433`（命令行参数）
- 其他选项使用 `development` 模板（命令行参数）
- 配置文件中的 `profile=production` 被忽略

---

## 配置验证

### 生成配置文件模板

```bash
pg_setup -g myconfig.conf
```

这会生成一个包含所有选项和注释的模板文件。

### 验证配置文件

使用 `--debug` 选项查看配置解析过程：

```bash
pg_setup -c myconfig.conf --debug
```

### 常见配置错误

1. **缺少等号**：
   ```ini
   # 错误
   data_directory /var/lib/postgresql/data
   
   # 正确
   data_directory=/var/lib/postgresql/data
   ```

2. **无效的布尔值**：
   ```ini
   # 错误
   start_server=YES  # 大小写敏感
   
   # 正确
   start_server=yes
   ```

3. **路径中的空格**：
   ```ini
   # 如果路径包含空格，不需要引号
   data_directory=/path/with spaces/data
   ```

4. **注释格式**：
   ```ini
   # 正确
   # 这是注释
   
   # 错误（行内注释不支持）
   port=5432 # 这不是注释
   ```

---

## 最佳实践

1. **使用配置模板**：
   - 从模板开始，只覆盖需要的选项
   - 减少配置错误

2. **安全存储密码**：
   - 使用 `pwfile` 而不是 `password`
   - 设置文件权限为 0600

3. **版本控制**：
   - 将配置文件加入版本控制
   - 不要提交包含密码的文件

4. **文档化**：
   - 在配置文件中添加注释
   - 说明每个选项的用途

5. **测试配置**：
   - 在测试环境中验证配置
   - 使用 `--debug` 检查配置解析

---

## 参考资料

- pg_setup README 文件
- PostgreSQL 官方文档：配置文件
- PostgreSQL 官方文档：客户端认证

