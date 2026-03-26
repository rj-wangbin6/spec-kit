# RGOS C 代码 DesignCheck 规则集
---

## 规则 1：ASID 类型问题（64位 MIPS）

**关键字**：`asid_cache`, `struct cpuinfo_mips`

**说明**：`cpu-info.h` 中 `struct cpuinfo_mips` 结构的 `asid_cache` 成员，如果是 `int` 类型则存在问题，应使用 `unsigned long` 类型。仅在 64 位 MIPS CPU 上存在，扫描结果需进一步核对。

---

## 规则 2：CPU 100% — scanf 格式符问题

**关键字**：`scanf`, `%lu`, `PRIu64`

**说明**：读取内容的代码 `scanf` 中使用了 `%lu`，若读取内容超过 32 位，在 32 位 ARM 处理器（使用 `.toolchain-arm-cortex_a9` 工具链）时会读取出错。需要显式使用 `PRIu64` 读取。扫描结果需进一步核对。

---

## 规则 3：efmp_buff_clone 报文合法性检测

**关键字**：`efmp_buff_clone`

**说明**：快转的报文克隆接口 `efmp_buff_clone()` 入口处对报文合法性检测，发现传进来的报文 data 区的起始位置加上报文的实际长度已经改写到了下一个 EFBUF，认为系统异常，打印当前堆栈信息，调用 `BUG()` 重启了该管理板。

---

## 规则 4：RG_THREAD_IS_IN_LIST 使用规范

**关键字**：`RG_THREAD_IS_IN_LIST`, `rg_thread_cancel`, `rg_thread_cancel_by_arg`  
**BUG**：220048

**说明**：`RG_THREAD_IS_IN_LIST` 接口适用于 insert 方式添加的伪线程，在取消时需要判断是否处于 list 中。注意 `rg_thread_cancel` 和 `rg_thread_cancel_by_arg` 是不同的接口。

---

## 规则 5：CPU 亲和性接口配对使用

**关键字**：`pthread_setaffinity_np`, `sched_setaffinity`, `kthread_bind`, `set_cpus_allowed`, `get_cores_affinity`, `get_cores_partition`

**说明**：在调用了 `pthread_setaffinity_np` / `sched_setaffinity` / `kthread_bind`（内核）/ `set_cpus_allowed`（内核）的同一个模块中，必须调用过 `get_cores_affinity` / `get_cores_partition` / `get_cores_affinity`（内核）这几个接口之一。

---

## 规则 6：禁用 mdelay，改用 msleep

**关键字**：`mdelay`, `msleep`  
**品控**：7402

**说明**：`mdelay` 会挂起 CPU，应改用 `msleep`。

---

## 规则 7：禁用 daemon 函数

**关键字**：`daemon`

**说明**：`daemon` 函数无法供 HAM 模块监控，应改用 `&` 方式启动。

---

## 规则 8：shmget 改用 shm_open

**关键字**：`shmget`, `shm_open`

**说明**：`shmget` 需改用 `shm_open` 创建共享内存，可以在 `/dev/shm` 下观察到使用情况。

---

## 规则 9：add_timer 改用 mod_timer

**关键字**：`add_timer`, `mod_timer`

**说明**：`add_timer` 改用 `mod_timer` 可以避免重复添加，更安全。

---

## 规则 10：del_timer 改用 del_timer_sync

**关键字**：`del_timer`, `del_timer_sync`

**说明**：`del_timer` 应改用 `del_timer_sync`。

---

## 规则 11：flock 改用 fcntl

**关键字**：`flock`, `fcntl`

**说明**：`flock` 不是 POSIX 标准的，父子进程会被继承，重启后锁不一定自动释放。应改用 `fcntl`。

---

## 规则 12：synchronize_rcu 改用 call_rcu

**关键字**：`synchronize_rcu`, `call_rcu`

**说明**：`synchronize_rcu` 属于同步调用，很耗时，可以替换为异步方式 `call_rcu`。

---

## 规则 13：禁用 pthread_cond_wait

**关键字**：`pthread_cond_wait`, `pthread_cond_timedwait`  
**品控**：7767

**说明**：不允许再用 `pthread_cond_wait`，要求各业务使用非阻塞的 `pthread_cond_timedwait()`。

---

## 规则 14：禁止调用 sync，改用 fsync

**关键字**：`sync`, `fsync`  
**BUG**：289366

**说明**：模块原则上禁止调用 `sync`。除了部分系统组件负责同步所有文件以外，所有组件都不准调用 `sync` 接口，只能调用 `fsync` 接口，以防被卡住。

---

## 规则 15：信号处理中禁止加锁挂起

**关键字**：信号处理函数、加锁

**说明**：信号处理中不能有加锁挂起操作。

---

## 规则 16：信号处理中禁用 pthread_exit

**关键字**：`pthread_exit`, 信号处理函数

**说明**：信号处理函数里调用 `pthread_exit()` 可能存在不安全，需要改造。

---

## 规则 17：ef pkt 操作配对

**关键字**：`efmp_get_current_pkt`, `efmp_put_current_pkt`

**说明**：`efmp_get_current_pkt` 和 `efmp_put_current_pkt` 使用要配对；调用 `efmp_put_current_pkt` 接口后不能再操作报文指针。

---

## 规则 18：efmp_buff_free 后禁止使用报文指针

**关键字**：`efmp_buff_free`, `EF_Lost`

**说明**：`efmp_buff_free` 之后的报文指针不得再使用；返回 `EF_Lost` 之后不能再使用报文指针；即判断返回值等于 `EF_Lost` 之后不能再操作报文指针。

---

## 规则 19：写文件必须调用 fsync

**关键字**：`fopen`, `open`, `fsync`, `O_RDONLY`

**说明**：
1. 调用 `fopen(path, mode)` 的地方，其中 `mode` 不是 `"r"` 或 `"rb"` 的调用处，没有执行 `fsync()` 函数。
2. 调用 `open(pathname, flags, mode)` 的地方，其中 `flags` 不是 `O_RDONLY` 的调用处，没有执行 `fsync()` 函数。

---

## 规则 20：检查 sys_open/sys_openat/filp_open 调用

**关键字**：`sys_open`, `sys_openat`, `filp_open`

**说明**：查找调用 `sys_open()` / `sys_openat()` / `filp_open()` 的地方。

---

## 规则 21：ioctl FIONBIO 第三个参数类型

**关键字**：`ioctl`, `FIONBIO`

**说明**：采用 `ioctl` 设置 socket 为非阻塞时（第二个参数为 `FIONBIO`），第三个参数指向的数据内容要为 `int` 类型，不能为 `long` 类型。

**正确例子**：
```c
int bset;
bset = 1;
ret = ioctl(fd, FIONBIO, (ulong)(&bset));
```

**错误例子**：
```c
unsigned long bset;
bset = 1;
ret = ioctl(fd, FIONBIO, &bset);
```

---

## 规则 22：禁止随意设置实时线程调度策略

**关键字**：`SCHED_FIFO`, `SCHED_RR`

**说明**：自研代码缺省情况下，业务不能随便将线程的调度策略设置为实时线程（`SCHED_FIFO` / `SCHED_RR`），有特殊需求需向系统组或总体组提出申请。

**背景**：
- Linux 内核调度策略：`SCHED_DEADLINE`（限期）、`SCHED_FIFO`（先进先出）、`SCHED_RR`（轮流调度）、`SCHED_NORMAL`（正常）、`SCHED_IDLE`（空闲）。
- FIFO 调度没有时间片，如果没有更高优先级实时进程且不睡眠，将一直霸占处理器。

**故障案例**：8612 厦门医学院 M18000-WS-ED 设备配置丢失。实时线程长时间占用 CPU 导致 ACL 线程得不到调度，导致配置丢失，也可能导致 HAM 重启设备或内核 RCU 检测机制打印 log。

---

## 规则 23：sqlite3_exec 出参指针需初始化

**关键字**：`sqlite3_exec`  
**BUG**：350182

**说明**：指针参数作为出参未初始化传入 `sqlite3_exec`，返回失败后 `sqlite3_exec` 也未对其进行初始化，后续 `free` 指针时导致野指针访问，产生 coredump。

**解决方案**：初始化为 `NULL`，接口返回时判断是否为 `NULL`，再释放内存。

---

## 规则 24：mkdir 返回值需检查 EEXIST

**关键字**：`mkdir`, `EEXIST`  
**BUG**：338173

**说明**：调用 `mkdir` 接口返回失败情况下，如 `errno` 是 `EEXIST` 说明目录已经存在，通常认为创建成功，否则可能走到异常分支处理。

**正确例子**：
```c
ret = mkdir(agent_dir, S_IRWXU);
if (ret != 0 && errno != EEXIST) {
    print_err("%s: mkdir failed\n", __func__);
    goto fail;
}
```

---

## 规则 25：禁止将 inotify_add_watch 返回值作为句柄监听

**关键字**：`inotify_add_watch`, `inotify_init`, `FD_SET`, `rg_thread_add_read`  
**BUG**：380238  
**优先级**：Major

**说明**：`inotify_add_watch` 的返回值不是句柄，不能作为监听函数的参数。应该监听的是 `inotify_init` 的返回值。

**检查规则**：把 `inotify_add_watch` 的返回值作为以下使用场景时直接告警：
- `rg_thread_add_read` 开头的函数
- `FD_SET(wd, xx)`
- 赋值给 poll 的参数（`xx.fd = wd`）

**错误例子**：
```c
inotifyfd = inotify_init();
wd = inotify_add_watch(inotifyfd, "/tmp/ham/", IN_CLOSE_WRITE | IN_CREATE | IN_MODIFY | IN_ISDIR);
FD_SET(wd, &readwds);           // 错误！应该用 inotifyfd
select(wd + 1, &readwds, ...);  // 错误！应该用 inotifyfd
```

---

## 规则 26：list_first_entry 前必须判断链表为空

**关键字**：`list_first_entry`, `list_empty`  
**BUG**：375045

**说明**：在使用 `list_first_entry` 时都需要判断 `list_empty`，否则在链表为空的情况下就会访问野指针导致进程死机。

---

## 规则 27：xmlNodeGetContent 返回值需 xmlFree 释放

**关键字**：`xmlNodeGetContent`, `xmlFree`

**说明**：调用 `xmlNodeGetContent` 获取到的返回值，如果非 `NULL`，则退出时需要调用 `xmlFree` 进行释放，否则会内存泄漏。

**示例**：
```c
value = xmlNodeGetContent(curnode);
if (value == NULL) {
    return ret;
}
// ... 使用 value ...
xmlFree(value);  // 必须释放
return ret;
```

---

## 规则 28：rdnd_chkpnt_snd CANDROP 模式丢包风险

**关键字**：`rdnd_chkpnt_snd`, `RDND_SND_FLG_NOWAIT`, `RDND_SND_FLG_CANDROP`

**说明**：调用 `rdnd_chkpnt_snd` 时，如果第三个参数 flag 为 `RDND_SND_FLG_NOWAIT | RDND_SND_FLG_CANDROP`，即使返回值为 `RDND_SND_OK` 成功，也可能存在丢包情况。业务需确认丢包是否需要重传。如果需要重传，则不能使用此 flag 组合。

**接口说明**：
- `0`：阻塞方式发送
- `RDND_SND_FLG_NOWAIT`：非阻塞方式，拥塞时返回 `RDND_SND_EAGAIN`
- `RDND_SND_FLG_NOWAIT | RDND_SND_FLG_CANDROP`：非阻塞方式，拥塞时**直接丢弃并返回 `RDND_SND_OK`**

---

## 规则 29：系统调用需处理 EINTR

**关键字**：`EINTR`, `select`, `poll`, `epoll`, `read`, `recv`  
**优先级**：Normal

**说明**：在调用会返回 `EINTR` 的系统调用时（如 `select`/`poll`/`epoll`、`read`/`recv` 等），需要检查返回值处理中是否包含了 `EINTR` 错误的处理。

---

## 规则 30：中断上下文禁用 GFP_KERNEL 申请内存

**关键字**：`spin_lock_bh`, `spin_unlock_bh`, `kmalloc`, `GFP_KERNEL`, `genlmsg_new`  
**优先级**：Major

**说明**：在中断上下文（如调用 `spin_lock_bh` 之后且在 `spin_unlock_bh` 之前）、tasklet 或内核定时器中，使用 `GFP_KERNEL` 参数申请内存（包括 `kmalloc` 和其他如 `genlmsg_new` 等），直接告警。

---

## 规则 31：Domain Socket 需忽略 SIGPIPE

**关键字**：`AF_UNIX`, `SOCK_SEQPACKET`, `SOCK_STREAM`, `SIGPIPE`, `SIG_IGN`

**说明**：使用基于连接的 domain socket 通信时，需要忽略信号 `SIGPIPE`，否则通信一端退出时，对端调用 `write` 会触发 `SIGPIPE` 信号导致进程退出。

**规则**：调用 `socket(AF_UNIX, SOCK_SEQPACKET, ...)` 或 `socket(AF_UNIX, SOCK_STREAM, ...)` 创建套接字的进程，要在创建套接字之前调用：
```c
signal(SIGPIPE, SIG_IGN);
```

---

## 规则 32：内核禁用 yield 函数

**关键字**：`yield`

**说明**：内核模块不能调用 `yield` 函数。`yield` 函数并不会让出 CPU，会导致 HAM 检测挂住。

---

## 规则 33：udelay/ndelay 参数不能超过 20000

**关键字**：`udelay`, `ndelay`

**说明**：内核模块 `udelay`/`ndelay` 参数值不能超过 20000，否则函数执行会失效。内核通用 `udelay`/`ndelay` 实现会判断参数大于 20000 就不支持该函数。

---

## 规则 34：sem_wait/sem_post 不得作为互斥锁使用

**关键字**：`sem_wait`, `sem_post`, `pthread_mutex_lock`, `pthread_mutex_unlock`

**说明**：`sem_wait()`/`sem_post()` 当作互斥锁使用时，因为 Octeon glibc 有 BUG，会导致锁保护失效（曾导致并发访问链表、访问非法地址后 coredump）。当作事件通告使用时不会引起问题。

**建议**：修改为 `pthread_mutex_lock()`/`pthread_mutex_unlock()`。

---

## 规则 35：sqlite3_prepare 改用 sqlite3_prepare_v2

**关键字**：`sqlite3_prepare`, `sqlite3_prepare_v2`  
**BUG**：374222

**说明**：`sqlite3_prepare` 需要使用 `sqlite3_prepare_v2` 来替代。

---

## 规则 36：自旋锁内禁止调用 filp_close

**关键字**：`filp_close`, `spin_lock`, `spin_unlock`, `spin_lock_bh`, `spin_unlock_bh`, `write_lock`, `write_unlock`

**说明**：`filp_close` 接口会挂起，不能在持有自旋锁时调用。否则：
1. 会在原子上下文发生调度（打印 `BUG: scheduling while atomic`）
2. 可能导致死锁

**禁止的使用模式**：
```
spin_lock      → filp_close → spin_unlock
spin_lock_bh   → filp_close → spin_unlock_bh
write_lock     → filp_close → write_unlock
write_lock_bh  → filp_close → write_unlock_bh
```

---

## 规则 37：内核禁用 wait_event

**关键字**：`wait_event`, `wait_event_timeout`, `wait_event_interruptible`

**说明**：业务内核模块不建议使用 `wait_event` 函数，`wait_event` 会使线程一直处于 `TASK_UNINTERRUPTIBLE` 状态，而被 hung_task 重启。应使用 `wait_event_timeout` 或 `wait_event_interruptible` 替代。

---

## 规则 38：禁用 pthread_cancel

**关键字**：`pthread_cancel`  
**BUG**：374218  
**优先级**：Major

**说明**：禁用 `pthread_cancel` 接口。在所有分支上发现有执行 `pthread_cancel()` 时，直接告警。

**背景**：`pthread_cancel` 主动杀线程操作，会导致被杀线程在拿到互斥锁之后直接退出，造成死锁。在多模块协同运行的复杂程序中，很容易在其他模块申请的锁、句柄、全局变量、内存、数据库等资源没处理完就杀掉了。最佳方式是让线程走到一个逻辑点时主动销毁。

---

## 规则 39：json_array add 到 json_obj 后不可单独释放

**关键字**：`json_object_put`, `json_object_object_add`, `json_object_new_array`

**说明**：创建 `json_obj` 和 `json_array`，当 `json_array` 通过 `json_object_object_add` 加入到 `json_obj` 后，`json_array` 不能调用 `json_object_put()` 释放内存，只需要释放 `json_obj` 即可。

**正确例子**：
```c
json_obj = json_object_new_object();
json_array = json_object_new_array();
json_object_array_add(json_array, json_object_new_int(1));
json_object_object_add(json_obj, "data", json_array);
// 只释放 json_obj，json_array 内存由 json_obj 管理
json_object_put(json_obj);
```

---

## 规则 40：分支判断语句后不可直接跟分号

**关键字**：`if`, `else if`, `switch`, `while`, `for`

**说明**：检查分支判断语句后直接出现 `;` 的情况，避免是不小心加的 `;` 导致语句异常执行：
1. `if (xxx) ;`
2. `else if (xxx) ;`
3. `switch (xxx) ;`
4. `while (xxx) ;`
5. `for (xxx) ;`

---

## 规则 41：VRF — SOCK_STREAM 创建需关注

**关键字**：`AF_INET`, `PF_INET`, `AF_INET6`, `PF_INET6`, `SOCK_STREAM`

**说明**：12.x 需要进行改动，关注 VRF 变动，每 VRF 创建一个 socket。检查调用 `socket` 函数且第一个参数为 `AF_INET`/`PF_INET`/`AF_INET6`/`PF_INET6`、第二个参数为 `SOCK_STREAM` 的地方。

---

## 规则 42：禁止对 SIGABRT 信号操作

**关键字**：`signal`, `sigaction`, `SIGABRT`

**说明**：禁止使用 `signal` 或 `sigaction` 函数对 `SIGABRT` 信号（数字为 6）操作，给出警告并要求项目内测前完成修订。

---

## 规则 43：net_client_add_dyn_arp_async 替换为 net_client_arp_entry_set

**关键字**：`net_client_add_dyn_arp_async`, `net_client_arp_entry_set`

**说明**：VRF 专项导入，原先接口 `net_client_add_dyn_arp_async` 没有传入 VRF 字段导致存在问题，需要替换成 `net_client_arp_entry_set` 接口。

---

## 规则 44：mod_timer 必须使用绝对时间

**关键字**：`mod_timer`, `jiffies`

**说明**：`mod_timer` 后面的时间要使用绝对时间（基于 `jiffies`）。

**正确例子**：
```c
mod_timer(&timer, jiffies + HZ);     // 1s 后触发定时器
mod_timer(&timer, jiffies + 1);      // 下一个 tick 触发定时器
```

---

## 规则 45：函数入参未使用检查

**关键字**：函数参数

**说明**：函数入参的每个参数，如果在函数中没有使用，可能有问题。

**示例**：
```c
void ABC(int arg1, int arg2, int arg3)
{
    // arg1 使用了
    // arg2 使用了
    // arg3 未使用 → 可能有问题
    return;
}
```

---

## 规则 46：链表节点重复添加检查

**关键字**：`list_add`, `list_del_init`

**说明**：链表添加节点后，没有摘除节点（`list_del_init`）又重新添加节点（`list_add`），会导致问题。

---

## 规则 47：dirname 后参数内容可能被破坏

**关键字**：`dirname`  
**品控 BUG**：11855

**说明**：`char *dirname(char *path)` 使用 `dirname` 函数，参数传递的缓存内容可能被破坏，不能再进行 `open` 等操作。

---

## 规则 48：nsm_msg_route_ipv4/ipv6 资源释放

**关键字**：`nsm_msg_route_ipv4`, `nsm_msg_route_ipv6`, `nsm_finish_route_ipv4`, `nsm_finish_route_ipv6`, `MTYPE_NSM_MSG_NEXTHOP_IPV4`, `MTYPE_NSM_MSG_NEXTHOP_IPV6`

**说明**：
- 使用 `struct nsm_msg_route_ipv4` 定义变量的函数，必须调用 `nsm_finish_route_ipv4(变量名)` 或 `XFREE(MTYPE_NSM_MSG_NEXTHOP_IPV4, 变量名->nexthop_opt)`。
- 使用 `struct nsm_msg_route_ipv6` 定义变量的函数，必须调用 `nsm_finish_route_ipv6(变量名)` 或 `XFREE(MTYPE_NSM_MSG_NEXTHOP_IPV6, 变量名->nexthop_opt)`。

---

## 规则 49：nsm_msg_route 访问 nexthop 必须访问 nexthop_opt

**关键字**：`nsm_msg_route_ipv4`, `nsm_msg_route_ipv6`, `nexthop`, `nexthop_opt`

**说明**：函数中出现 `struct nsm_msg_route_ipv4`（或 `struct nsm_msg_route_ipv6`），并且有访问 `nexthop` 数组，则必定要有访问 `nexthop_opt` 的实现。

---

## 规则 50：dev_get_by_index 等需 dev_put 配对

**关键字**：`rg_dev_get_by_index`, `dev_get_by_index`, `dev_hold`, `dev_put`

**说明**：调用了 `rg_dev_get_by_index`、`dev_get_by_index`、`dev_hold` 等接口后，都需要使用 `dev_put` 减少计数，以防无法删除接口。

---

## 规则 51：vrfk_get_netns 等需 put_net 配对

**关键字**：`vrfk_get_netns`, `get_net`, `get_net_ns_by_vrf`, `put_net`

**说明**：调用了 `vrfk_get_netns`、`get_net`、`get_net_ns_by_vrf` 等接口后，都需要使用 `put_net` 减少计数，以防无法删除 VRF 网络命名空间。

---

## 规则 52：禁用 sync_filesystem，改用 vfs_fsync

**关键字**：`sync_filesystem`, `vfs_fsync`

**说明**：所有自研组件都不准调用 `sync_filesystem` 接口（特殊需求除外），可以使用 `vfs_fsync` 接口替换，以防被卡住。

---

## 规则 53：不建议使用 pthread_attr_setstacksize

**关键字**：`pthread_attr_setstacksize`, `PTHREAD_STACK_MIN`

**说明**：不允许使用 `pthread_attr_setstacksize`。

**背景**：`select` 无感知支持到监听 65535 个 fd，扩大了 `fd_set` 的大小，会导致应用程序栈空间使用增加。部分线程设置栈空间大小过小（如 `PTHREAD_STACK_MIN`），可能导致栈溢出。

**提示**：线程的用户栈长度使用默认值（8MB）即可。增大用户栈长度只是增大虚拟内存，如果没有访问不会分配并映射到物理页。如果设置太小，可能会导致栈溢出。

---

## 规则 54：禁止使用已删除的配置宏

**关键字**：能力改造、配置宏

**说明**：12.1PL1 进行能力改造中，检查到的配置宏不允许各组件继续使用。

---

## 规则 55：spin_lock_irqsave / spin_unlock_irqrestore 配对使用

**关键字**：`spin_lock_irqsave`, `spin_unlock_irqrestore`

**说明**：`spin_lock_irqsave` / `spin_unlock_irqrestore` 需要配对使用。

---

## 规则 56：TIPC 非阻塞模式风险检查

**关键字**：`AF_TIPC`, `fcntl`, `O_NONBLOCK`

**说明**：检查使用 TIPC 协议非阻塞模式的模块，存在一定风险。

**特征**：
1. 使用 `socket(AF_TIPC, ...)` 创建 TIPC 接口
2. 并且调用 `fcntl` 设置为 `O_NONBLOCK` 模式

**示例**：
```c
flags = fcntl(sockfd, F_GETFL, 0);
fcntl(sockfd, F_SETFL, flags | O_NONBLOCK);
```

---

## 规则 57：si_meminfo/si_swapinfo 禁止在定时器中断中调用

**关键字**：`si_meminfo`, `si_swapinfo`

**说明**：内核提供的 `si_meminfo` 和 `si_swapinfo` 接口内部实现可能带有锁操作，如果在内核模块的定时器中断中调用，则很可能出现死锁。建议只在内核线程中调用。

---

## 规则 58：snprintf/sprintf 必须使用格式化参数

**关键字**：`snprintf`, `sprintf`, `%s`  
**故障**：25969

**说明**：`snprintf`/`sprintf` 格式化字符串时必须带上 `%s` 进行格式化，否则字符串中存在 `%` 字符时会出现异常。

**检查规则**：
- `snprintf` 只有 3 个参数 → 提示错误
- `sprintf` 只有 2 个参数 → 提示错误

---

## 规则 59：内存操作函数地址参数合法性

**关键字**：`strcpy`, `strncpy`, `memcpy`, `memcmp`, `memset`, `snprintf`, `sprintf`  
**故障**：28033

**说明**：采用 `strcpy`/`strncpy`/`memcpy`/`memcmp`/`memset`/`snprintf`/`sprintf` 时，需要判断获取的地址是否是指针的地址（而非指针所指向的地址）。可以增加第一个参数合法性校验。

---

## 规则 60：fopen "a" 模式用 ftell 前必须 fseek

**关键字**：`fopen`, `ftell`, `fseek`

**说明**：调用 `fopen` 以 `"a"` 或 `"a+"` 模式打开文件，调用 `ftell` 之前必须调用 `fseek`。在某些平台上（如 AP），不调用 `fseek` 时 `ftell` 将始终返回 0，无论文件大小。

**正确例子**：
```c
fp = fopen(path, "a");
fseek(fp, 0, SEEK_END);
size = ftell(fp);  // 此时才能正确返回文件大小
```

---

## 规则 61：MIB get/getn 函数返回值规范

**关键字**：`SNMP_NO_SUCH_INSTANCE`, `SNMP_NO_ERROR`, `SNMP_END_VIEW`  
**BUG**：327397

**说明**：
1. `get` 函数只能返回 `SNMP_NO_SUCH_INSTANCE` 和 `SNMP_NO_ERROR`
2. `getn` 函数只能返回 `SNMP_END_VIEW` 和 `SNMP_NO_ERROR`

返回其他的值都是非法值。只有找到表项内容才返回 `SNMP_NO_ERROR`，否则都要返回规定的返回值。

---

## 规则 62：fork 后子进程禁止获取锁

**关键字**：`fork`, `exec`, `pthread_mutex_lock`

**说明**：进程调用 `fork()` 之后，且在调用 `exec()` 之前或没有执行 `exec()`，如果在 `fork()` 返回值为 0 的子进程流程中有获取锁（`pthread_mutex_lock()` 等接口）或者调其他函数的操作，则提示告警。

---

## 规则 63：RG_MOM_DEL 后禁止使用 res_mom_hash_res_t 转换

**关键字**：`RG_MOM_DEL`, `res_mom_hash_res_t`

**说明**：判断 `RG_MOM_DEL` 之后是否有使用 `res_mom_hash_res_t` 转换 hash 的操作。

---

## 规则 64：protobuf-c 变量必须用生成的宏初始化

**关键字**：`protobuf-c`, `__INIT`

**说明**：protobuf-c 生成的变量（特征：大写字母开头，中间有双下划线）必须通过 protobuf-c 自动生成的初始化宏进行有效初始化。

**初始化宏特征**：与变量名相同，所有大写字母前增加单下划线，小写字母转为大写字母，并在末尾增加 `__INIT`。

---

## 规则 65：禁止改写 config.text

**关键字**：`config.text`, `CLI_STARTUP_CFG_FILE`, `cli_get_config_dir`  
**优先级**：Warning

**说明**：检查代码文件中有使用到 `config.text`、宏 `CLI_STARTUP_CFG_FILE` 或接口 `cli_get_config_dir`，将报 Warning，需要业务确认是否有改写 `config.text` 配置文件的行为。

---

## 规则 66：禁止使用已废弃的配置宏

**关键字**：配置宏、Makefile

**说明**：代码和 Makefile 中都需要检查是否还遗留已删除的宏。如果存在以下宏则通知组件负责人整改：

| 废弃宏 |
|---|
| `CONFIG_rg-dev_dcm_lib` |
| `CONFIG_rg-dev_dcm_daemon` |
| `CONFIG_rg-dev_dm_lib` |
| `KCONFIG_rg-proc-ham-dep` |
| `CONFIG_rg-dev_s12k_proc` |
| `CONFIG_rg-dev_sw_lib` |
| `CONFIG_RAS_SEM` |
| `CONFIG_RAS_PSH` |
| `CONFIG_DM_SWITCH` |
| `CONFIG_DM_MC` |

---

## 规则 67：rg_mom_subscribe 后不可直接 rg_mom_unsubscribe

**关键字**：`rg_mom_subscribe`, `rg_mom_unsubscribe`

**说明**：`rg_mom_subscribe()` 函数后面不能马上跟着 `rg_mom_unsubscribe()`，而是应该把 `rg_mom_unsubscribe()` 函数放在 `rg_mom_subscribe()` 的回调函数中。

---

## 规则 68：禁止使用指定的时间相关接口

**关键字**（禁用列表）：

| 禁用接口 |
|---|
| `setitimer` / `getitimer` |
| `timer_create` / `timer_delete` / `timer_gettime` / `timer_settime` |
| `getboottime` / `getboottime64` |
| `getnstimeofday` / `getnstimeofday64` |
| `do_gettimeofday` |
| `ktime_get_real` / `ktime_get_real_ts` / `ktime_get_real_ts64` |
| `ktime_get_coarse_real_ts64` / `ktime_get_coarse_real` |
| `ktime_get_real_ns` / `ktime_get_real_fast_ns` / `ktime_get_real_seconds` / `__ktime_get_real_seconds` |
| `ktime_get_snapshot` |
| `current_kernel_time` / `current_kernel_time64` |
| `get_seconds` |
| `time` / `time32` / `gettimeofday` / `clock_gettime` |
| `pthread_cond_init` |
| `sem_timedwait` |
| `mq_timedsend` / `mq_timedreceive` |

---

## 规则 69 & 70：rg_monotime 多次获取必须使用 timer_sub

**关键字**：`rg_monotime`, `timer_sub`

**说明**：在同一函数中，禁止出现多次获取 `rg_monotime`，却没有使用 `timer_sub` 计算差值。

---

## 规则 71：显式声明对齐方式检查

**关键字**：`__attribute__((aligned(`, `aligned`

**说明**：`__attribute__((aligned(8)))` 等显式声明对齐方式的代码需要检查（不只检查 8 字节对齐，所有对齐都检查）。

---

## 规则 72：禁用 sysconf(_SC_CLK_TCK)

**关键字**：`sysconf`, `_SC_CLK_TCK`

**说明**：禁止使用 glibc 接口 `sysconf(_SC_CLK_TCK)`。

---

## 规则 73：pthread_cond_timedwait 返回值 ETIMEDOUT 使用风险

**关键字**：`pthread_cond_timedwait`, `ETIMEDOUT`  
**品控故障**：60868

**说明**：使用 `pthread_cond_timedwait` 时，对其返回值进行 `ETIMEDOUT` 比较判断的地方需要告警，定时器可能无法到期执行到。

**错误原因**：
1. `pthread_cond_timedwait` 中，事件触发和定时器到期执行的不是同一件事
2. 当事件条件大量触发时，想借助定时器到期执行的逻辑可能长期无法执行到

**错误示例**：
```c
while(1) {
    timeout.tv_sec += REF_RES_INTERVAL;
    ret = pthread_cond_timedwait(arg1, arg2, &timeout);
    if (ret == ETIMEDOUT) {
        FUNC_B();  // 可能长期无法执行到
    }
}
```

---

## 规则 74：TCPIP 模块接口查找需预创建

**关键字**：`tcpip_nc_get_reg_netif`, `netif_index2block`, `netif_create_netifcb_ex`, `if_index2ifp`, `if_index2ifp_w_create`  
**BUG**：1247918

**说明**：在 TCPIP 模块中，如果根据 ifx 查找内部接口返回失败，需要再调用"预创建内部接口"进行预创建。

**检查规则**：
- **IPv4**：
  - 同一函数中存在 `tcpip_nc_get_reg_netif` 但不存在 `netif_create_netifcb_ex` → 逻辑缺陷
  - 同一函数中存在 `netif_index2block` 但不存在 `netif_create_netifcb_ex` → 逻辑缺陷
- **IPv6**：
  - 同一函数中存在 `if_index2ifp` 但不存在 `if_index2ifp_w_create` → 逻辑缺陷

## 规则75：内存泄漏（仅限静态可证泄漏路径）**
**检查点**：
1. 存在显式内存分配（`malloc`/`kmalloc`等），结果赋给局部指针变量。
2. 函数有多个返回点，某路径未释放内存且未转移所有权（未返回/未存全局）。
3. 指针为局部变量，函数返回后不可达。
**禁止报告**：  
- 所有权转移（返回/存全局）  
- 释放依赖运行时状态  
- 跨函数分配释放  
- 无明确泄漏路径的"风格问题"  
- 链表节点摘除后指针未丢失  

## 规则76：使用已释放内存**
**检查点**：
- 访问已释放资源（解引用释放后指针）  
- 链表遍历未用安全方法（如`list_for_each_safe`）  
- 局部变量地址传全局/异步上下文  
- 栈空间回收后访问指针  

## 规则77：变量未有效初始化**
**检查点**：
- 变量/指针使用前未初始化（野指针）  
- 结构体成员初始化遗漏  
- 函数出口返回值未初始化  
**禁止报告**：  
- 数据结构指针成员已初始化  
- 临时变量直接赋值  
- 无确切证据  

## 规则78：局部变量过大导致栈溢出**
**检查点**：
- 局部变量大小确知 > 512字节（需堆分配）  
- 递归调用累计栈空间超限  
**禁止报告**：不确定大小的局部变量  

## 规则79：异步调用使用临时变量（仅限明确生命周期冲突）**
**检查点**：
1. 栈变量地址传明确异步机制（任务队列/全局链表/回调注册等）
2. 异步操作在函数返回后执行，变量未延长生命周期
3. 异步代码会解引用该指针
**禁止报告**：  
- 接收方非真正异步  
- 本函数内同步使用  
- 无证据指针会被异步使用  

## 规则80：关中断下任务调度**
**检查点**：
- 关中断期间调用调度接口（如`schedule()`）  
- 关中断时间超系统喂狗周期  
- 破坏临界区保护  

## 规则81：使用错误变量/数据结构（高置信度）**
**检查点**：
1. **拷贝粘贴错误**：重复逻辑分支使用语义不符的变量（如`if(typeA)用configA；if(typeB)误用configA`）
2. **分支条件矛盾**：条件重复/互斥导致分支不可达（可静态确认）
3. **类型误用**：野指针解引用/混淆链表头与节点/访问不存在成员
**禁止报告**：  
- 仅变量名相似无逻辑矛盾  
- static函数未做非空判断  

## 规则82：内存操作越界（仅限可证问题）**
**检查点**：
1. 拷贝长度 > 目标/源缓冲区大小（长度编译时可确定）
2. `strncpy`等未预留终止符且长度>=缓冲区大小
3. 数组下标为负数或>=数组长度（常量赋值）
**禁止报告**：  
- 长度/下标来自运行时变量  
- 仅使用"不安全函数"无越界证据  

## 规则83：加解锁未配对**
**检查点**：
- 加锁后漏解锁  
- 配对操作缺失（如`malloc`/`free`）  
- 全局变量互斥访问错误  
**注意**：加锁失败不视为未配对  

## 规则84：循环结构错误**
**检查点**：
- 基础语法错误导致死循环  
- 缺少退出逻辑（无限循环）  

## 规则85：printf参数不匹配（仅限字面量格式串）**
**检查点**：
1. 格式串为字符串字面量
2. 占位符数量 != 参数数量（可静态计数）
3. 占位符类型与参数类型冲突（如`%s`传`int`）
**禁止报告**：  
- 格式串非字面量  
- 参数通过可变宏传递  
- 类型不匹配依赖平台API  

