# pg_setup 快速入门指南

## 最简单的使用方式

```bash
# 交互式安装（推荐首次使用）
pg_setup
```

## 常用命令

### 开发环境快速安装
```bash
pg_setup -D ~/pgdata -P development
```

### 生产环境安装
```bash
pg_setup -D /var/lib/postgresql/data -U postgres -W -P production --no-start
```

### 测试环境安装
```bash
pg_setup -D /tmp/testdb -P test
```

### 使用配置文件
```bash
# 生成配置文件模板
pg_setup -g myconfig.conf

# 编辑配置文件
vi myconfig.conf

# 使用配置文件安装
pg_setup -c myconfig.conf
```

### 静默安装（自动化脚本）
```bash
pg_setup -s -D /var/lib/postgresql/data -U postgres --pwfile=/etc/postgresql/pgpass -P production
```

## 配置模板说明

| 模板 | 认证方式 | 端口 | 连接数 | 自动启动 | 适用场景 |
|------|---------|------|--------|---------|---------|
| development | trust | 5432 | 20 | 是 | 本地开发 |
| production | scram-sha-256 | 5432 | 100 | 否 | 生产环境 |
| test | trust | 5433 | 10 | 是 | 自动化测试 |

## 常用参数速查

| 参数 | 说明 | 示例 |
|------|------|------|
| -D, --pgdata | 数据目录 | -D /var/lib/postgresql/data |
| -U, --username | 超级用户名 | -U postgres |
| -W, --pwprompt | 提示输入密码 | -W |
| -p, --port | 端口号 | -p 5432 |
| -P, --profile | 配置模板 | -P development |
| -E, --encoding | 字符编码 | -E UTF8 |
| -L, --locale | 区域设置 | -L en_US.UTF-8 |
| -A, --auth | 认证方式 | -A scram-sha-256 |
| -s, --silent | 静默模式 | -s |
| -c, --config-file | 配置文件 | -c myconfig.conf |
| -g, --generate-config | 生成配置模板 | -g myconfig.conf |
| --start | 自动启动服务器 | --start |
| --no-start | 不自动启动 | --no-start |

## 安装后操作

### 连接到数据库
```bash
psql -h localhost -p 5432 -U postgres
```

### 启动/停止/重启服务器
```bash
pg_ctl -D /path/to/data start
pg_ctl -D /path/to/data stop
pg_ctl -D /path/to/data restart
```

### 查看服务器状态
```bash
pg_ctl -D /path/to/data status
```

## 常见问题快速解决

### 端口被占用
```bash
pg_setup -D /path/to/data -p 5433
```

### 数据目录已存在
```bash
rm -rf /path/to/data
pg_setup -D /path/to/data
```

### 权限不足
```bash
sudo mkdir -p /var/lib/postgresql/data
sudo chown $USER /var/lib/postgresql/data
pg_setup -D /var/lib/postgresql/data
```

## 获取帮助

```bash
# 查看帮助信息
pg_setup --help

# 查看版本
pg_setup --version
```

详细文档请参阅 README 文件。
