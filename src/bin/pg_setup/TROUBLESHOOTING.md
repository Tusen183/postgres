# pg_setup 故障排查指南

本文档提供 pg_setup 常见问题的详细排查步骤和解决方案。

## 目录

1. [安装前问题](#安装前问题)
2. [安装过程问题](#安装过程问题)
3. [服务器启动问题](#服务器启动问题)
4. [连接问题](#连接问题)
5. [配置问题](#配置问题)
6. [权限问题](#权限问题)
7. [调试技巧](#调试技巧)

---

## 安装前问题

### 问题 1：数据目录已存在且非空

**错误信息：**
```
ERROR: data directory "/path/to/data" exists and is not empty
```

**原因：**
pg_setup 不会覆盖现有的数据库集群，以防止数据丢失。

**解决方法：**

1. 检查目录内容：
   ```bash
   ls -la /path/to/data
   ```

2. 如果确认可以删除：
   ```bash
   rm -rf /path/to/data
   ```

3. 或者备份后删除：
   ```bash
   mv /path/to/data /path/to/data.backup.$(date +%Y%m%d)
   ```

4. 或者使用不同的目录：
   ```bash
   pg_setup -D /path/to/new/data
   ```

**预防措施：**
- 在运行 pg_setup 前确认数据目录路径
- 使用 `--debug` 选项查看详细信息

---

### 问题 2：端口已被占用

**错误信息：**
```
ERROR: port 5432 is already in use
```

**原因：**
另一个进程（可能是另一个 PostgreSQL 实例）正在使用该端口。

**诊断步骤：**

1. 检查端口占用情况：
   ```bash
   # Linux/macOS
   netstat -an | grep 5432
   # 或
   lsof -i :5432
   ```

2. 查找 PostgreSQL 进程：
   ```bash
   ps aux | grep postgres
   ```

**解决方法：**

方法 1：使用不同端口
```bash
pg_setup -D /path/to/data -p 5433
```

方法 2：停止占用端口的进程
```bash
# 如果是 PostgreSQL
pg_ctl -D /old/data/directory stop

# 如果是其他进程，找到 PID 后
kill <PID>
```

方法 3：使用测试模板（自动使用端口 5433）
```bash
pg_setup -D /path/to/data -P test
```

---

### 问题 3：权限不足

**错误信息：**
```
ERROR: could not create directory "/path/to/data": Permission denied
```

**原因：**
当前用户对指定路径没有写权限。

**解决方法：**

方法 1：使用用户有权限的目录
```bash
pg_setup -D ~/pgdata
```

方法 2：创建目录并设置权限
```bash
sudo mkdir -p /var/lib/postgresql/data
sudo chown $USER:$USER /var/lib/postgresql/data
pg_setup -D /var/lib/postgresql/data
```

方法 3：使用 sudo（不推荐）
```bash
# 不推荐：会导致权限问题
sudo pg_setup -D /var/lib/postgresql/data
```

**最佳实践：**
- PostgreSQL 应以非 root 用户运行
- 数据目录应归 PostgreSQL 用户所有
- 目录权限应为 0700

---

## 安装过程问题

### 问题 4：无效的字符编码

**错误信息：**
```
ERROR: invalid encoding name "XXX"
```

**原因：**
指定的字符编码不被 PostgreSQL 支持。

**解决方法：**

1. 查看支持的编码：
   ```bash
   # 如果已有 PostgreSQL 安装
   psql -l
   ```

2. 使用常见的有效编码：
   - UTF8（推荐）
   - SQL_ASCII
   - LATIN1
   - EUC_JP
   - EUC_CN

3. 重新运行：
   ```bash
   pg_setup -D /path/to/data -E UTF8
   ```

---

### 问题 5：无效的区域设置

**错误信息：**
```
ERROR: invalid locale name "xxx"
```

**原因：**
指定的区域设置在系统中未安装。

**诊断步骤：**

1. 查看系统可用的区域设置：
   ```bash
   locale -a
   ```

2. 查看当前系统区域设置：
   ```bash
   locale
   ```

**解决方法：**

方法 1：使用系统支持的区域设置
```bash
pg_setup -D /path/to/data -L en_US.UTF-8
```

方法 2：安装所需的区域设置
```bash
# Debian/Ubuntu
sudo locale-gen zh_CN.UTF-8
sudo update-locale

# RHEL/CentOS
sudo localedef -i zh_CN -f UTF-8 zh_CN.UTF-8
```

方法 3：使用 C locale（通用但功能有限）
```bash
pg_setup -D /path/to/data -L C
```

---

### 问题 6：initdb 执行失败

**错误信息：**
```
ERROR: initdb failed with exit code X
```

**原因：**
底层 initdb 命令执行失败，可能有多种原因。

**诊断步骤：**

1. 使用调试模式查看详细信息：
   ```bash
   pg_setup -D /path/to/data --debug
   ```

2. 检查磁盘空间：
   ```bash
   df -h /path/to/data
   ```

3. 检查目录权限：
   ```bash
   ls -ld /path/to/data
   ```

4. 检查系统日志：
   ```bash
   dmesg | tail
   journalctl -xe
   ```

**常见原因和解决方法：**

原因 1：磁盘空间不足
```bash
# 清理空间或使用其他磁盘
df -h
du -sh /path/to/data
```

原因 2：文件系统不支持
```bash
# 某些网络文件系统可能不支持
# 使用本地文件系统
```

原因 3：SELinux 限制
```bash
# 临时禁用 SELinux
sudo setenforce 0

# 或配置 SELinux 策略
sudo chcon -R -t postgresql_db_t /path/to/data
```

---

## 服务器启动问题

### 问题 7：服务器启动失败

**错误信息：**
```
ERROR: could not start server
```

**诊断步骤：**

1. 检查 PostgreSQL 日志：
   ```bash
   cat /path/to/data/log/postgresql-*.log
   # 或
   tail -f /path/to/data/log/postgresql-*.log
   ```

2. 手动启动查看详细错误：
   ```bash
   pg_ctl -D /path/to/data -l logfile start
   ```

3. 检查配置文件：
   ```bash
   cat /path/to/data/postgresql.conf
   ```

**常见原因和解决方法：**

原因 1：端口冲突
```bash
# 修改端口
vi /path/to/data/postgresql.conf
# 找到 port = 5432 并修改
```

原因 2：监听地址配置错误
```bash
# 检查 listen_addresses
grep listen_addresses /path/to/data/postgresql.conf
```

原因 3：共享内存不足
```bash
# 检查系统限制
ipcs -l

# 调整 postgresql.conf
# shared_buffers = 128MB  # 减小值
```

原因 4：文件描述符限制
```bash
# 检查限制
ulimit -n

# 增加限制
ulimit -n 4096
```

---

### 问题 8：服务器启动后立即停止

**症状：**
服务器启动但几秒后停止。

**诊断步骤：**

1. 查看日志文件最后几行：
   ```bash
   tail -50 /path/to/data/log/postgresql-*.log
   ```

2. 检查系统资源：
   ```bash
   free -h
   df -h
   ```

**常见原因：**

1. 配置文件语法错误
2. 内存不足
3. 磁盘空间不足
4. 权限问题

**解决方法：**
根据日志中的具体错误信息进行修复。

---

## 连接问题

### 问题 9：无法连接到数据库

**错误信息：**
```
psql: error: could not connect to server: Connection refused
```

**诊断步骤：**

1. 确认服务器正在运行：
   ```bash
   pg_ctl -D /path/to/data status
   ```

2. 检查监听地址和端口：
   ```bash
   grep listen_addresses /path/to/data/postgresql.conf
   grep port /path/to/data/postgresql.conf
   ```

3. 测试端口连接：
   ```bash
   telnet localhost 5432
   # 或
   nc -zv localhost 5432
   ```

4. 检查防火墙：
   ```bash
   # Linux
   sudo iptables -L -n | grep 5432
   sudo firewall-cmd --list-all
   ```

**解决方法：**

方法 1：启动服务器
```bash
pg_ctl -D /path/to/data start
```

方法 2：修改监听地址
```bash
# 编辑 postgresql.conf
listen_addresses = 'localhost'  # 或 '*' 允许所有
```

方法 3：配置防火墙
```bash
# 允许 PostgreSQL 端口
sudo firewall-cmd --add-port=5432/tcp --permanent
sudo firewall-cmd --reload
```

---

### 问题 10：认证失败

**错误信息：**
```
psql: error: FATAL: password authentication failed for user "postgres"
```

**原因：**
密码错误或认证配置不正确。

**解决方法：**

方法 1：检查 pg_hba.conf
```bash
cat /path/to/data/pg_hba.conf
```

方法 2：临时使用 trust 认证（仅用于恢复访问）
```bash
# 编辑 pg_hba.conf
# 将认证方法改为 trust
# local   all   all   trust
# host    all   all   127.0.0.1/32   trust

# 重启服务器
pg_ctl -D /path/to/data restart

# 连接并修改密码
psql -U postgres
ALTER USER postgres PASSWORD 'newpassword';

# 恢复安全的认证方法
# 编辑 pg_hba.conf 改回 scram-sha-256
# 再次重启
```

---

## 配置问题

### 问题 11：配置文件解析错误

**错误信息：**
```
WARNING: ignoring invalid line X in configuration file
```

**原因：**
配置文件格式不正确。

**解决方法：**

1. 检查配置文件格式：
   ```bash
   cat -A myconfig.conf  # 显示所有字符
   ```

2. 确保格式正确：
   - 使用 `key=value` 格式
   - 注释以 `#` 开头
   - 没有多余的空格或特殊字符

3. 使用生成的模板作为参考：
   ```bash
   pg_setup -g template.conf
   diff myconfig.conf template.conf
   ```

---

## 权限问题

### 问题 12：数据目录权限不正确

**错误信息：**
```
WARNING: data directory permissions are incorrect
```

**解决方法：**

```bash
# 修正权限
chmod 700 /path/to/data
chown $USER:$USER /path/to/data

# 递归修正所有文件
chmod -R u=rwX,go= /path/to/data
```

---

## 调试技巧

### 启用详细日志

1. 使用 pg_setup 的调试模式：
   ```bash
   pg_setup -D /path/to/data --debug
   ```

2. 保留失败时的文件：
   ```bash
   pg_setup -D /path/to/data --noclean
   ```

3. 配置 PostgreSQL 详细日志：
   ```bash
   # 编辑 postgresql.conf
   log_min_messages = debug5
   log_connections = on
   log_disconnections = on
   log_statement = 'all'
   ```

### 手动验证步骤

1. 测试 initdb：
   ```bash
   initdb -D /path/to/data -E UTF8 -U postgres
   ```

2. 测试服务器启动：
   ```bash
   pg_ctl -D /path/to/data -l logfile start
   ```

3. 测试连接：
   ```bash
   psql -h localhost -p 5432 -U postgres -d postgres
   ```

### 收集诊断信息

创建诊断报告：
```bash
#!/bin/bash
echo "=== System Information ===" > diagnostic.txt
uname -a >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Disk Space ===" >> diagnostic.txt
df -h >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== PostgreSQL Processes ===" >> diagnostic.txt
ps aux | grep postgres >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== Port Usage ===" >> diagnostic.txt
netstat -an | grep 5432 >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== PostgreSQL Configuration ===" >> diagnostic.txt
cat /path/to/data/postgresql.conf >> diagnostic.txt
echo "" >> diagnostic.txt

echo "=== PostgreSQL Logs ===" >> diagnostic.txt
tail -100 /path/to/data/log/postgresql-*.log >> diagnostic.txt
```

---

## 获取帮助

如果以上方法都无法解决问题：

1. 查看 PostgreSQL 官方文档
2. 搜索 PostgreSQL 邮件列表归档
3. 在 PostgreSQL 社区论坛提问
4. 提交 bug 报告

提问时请提供：
- pg_setup 版本（`pg_setup --version`）
- 操作系统和版本
- 完整的错误信息
- 相关的日志文件
- 使用的命令和参数
