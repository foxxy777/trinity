# Trinity

**一个从零手写的 RV64GC 乱序双发射处理器，纯 Verilog/SystemVerilog 实现。**

## 项目简介

Trinity 是一个教学/学习目的的 RISC-V 处理器项目，从 2024 年 10 月开始，由两位开发者合作完成。项目经历了从顺序核到乱序核的完整演进过程，使用 Verilator + Difftest（香山框架）进行仿真验证。

## 微架构特征

| 特性 | 描述 |
|------|------|
| **指令集** | RV64GC（RV64IMAC + F/D 扩展） |
| **发射方式** | 乱序双发射 |
| **ROB 大小** | 64 项 |
| **发射队列** | Age-based OOO Issue Queue |
| **寄存器重命名** | 64 物理寄存器，Speculative RAT + Arch RAT |
| **分支预测** | BHT（2-bit 饱和计数器）+ BTB + Scoreboard |
| **L1 ICache** | 2-way 组相联，512-bit 宽取指 |
| **L1 DCache** | 2-way 组相联，blocking cache |
| **总线接口** | 自定义 DDR 总线（simddr 模拟） |
| **Load/Store** | Load-Store Forwarding，Store Queue |

## 模块结构

```
vsrc/
├── SimTop.sv              # 仿真顶层（CPU + DDR 模型）
├── core_top.sv            # CPU 顶层，连接前端/后端/访存
├── frontend/              # 前端
│   ├── ifu_top.v          # 取指单元
│   ├── bpu.v              # 分支预测单元
│   ├── bht.v              # 分支历史表（2-bit 饱和计数器）
│   ├── btb.v              # 分支目标缓冲
│   ├── frontend.v         # 前端流水线控制
│   ├── ibuffer.v          # 指令缓冲
│   ├── fifo_ibuffer.v     # FIFO 指令缓冲
│   ├── instr_admin.v      # 指令管理/重定向处理
│   └── pc_ctrl.v          # PC 控制逻辑
├── backend/
│   ├── backend.sv         # 后端顶层
│   ├── idu/
│   │   ├── idu_top.v      # 译码单元
│   │   └── decoder.v      # 指令解码器
│   ├── iru/
│   │   ├── iru_top.sv     # 重命名单元
│   │   ├── rename.sv      # 寄存器重命名逻辑
│   │   ├── spec_rat.sv    # 推测寄存器别名表
│   │   ├── arch_rat.sv    # 架构寄存器别名表
│   │   └── freelist.sv    # 空闲物理寄存器列表
│   ├── isu/
│   │   ├── isu_top.sv     # 发射单元
│   │   ├── dispatch.sv    # 分发逻辑
│   │   ├── busy_table.sv  # 忙表
│   │   ├── isq/           # 发射队列
│   │   │   ├── int_isq.sv       # 整数发射队列
│   │   │   ├── age_deq_policy.sv      # 年龄优先出队策略
│   │   │   └── age_deq_policy_ooo.sv  # OOO 年龄出队策略
│   │   ├── rob/            # 重排序缓冲
│   │   │   ├── rob.sv
│   │   │   └── robentry.sv
│   │   └── pregfile_*.sv   # 物理寄存器堆
│   └── exu/
│       ├── exu_top.sv     # 执行单元
│       └── fu/            # 功能单元
│           ├── alu.sv     # 算术逻辑单元
│           ├── agu.sv     # 地址生成单元
│           ├── bju.sv     # 跳转分支单元（含 Scoreboard）
│           └── muldiv.sv  # 乘除法单元
├── mem/
│   ├── mem_top.sv         # 访存单元顶层
│   ├── loadunit.sv        # Load 单元
│   ├── storeunit.sv       # Store 单元
│   ├── storequeue.sv      # Store Queue
│   ├── dcache_arb.sv      # DCache 仲裁器
│   └── mmu/
│       └── dtlb.sv        # 数据 TLB
├── cache/
│   ├── icache.v           # 指令 Cache（2-way）
│   ├── dcache.v           # 数据 Cache（2-way）
│   ├── cache_tagarray.v   # Tag 阵列
│   └── cache_dataarray.v  # Data 阵列
├── sim_ram/
│   ├── simddr.v           # DDR 内存模型
│   └── channel_arb.v      # 通道仲裁器
└── include/
    └── defines.sv         # 全局参数定义
```

## 开发历程

### Phase 0：项目启动（2024.10.23 - 2024.10.25）

- 搭建项目框架，加入 difftest submodule
- 实现 simddr 内存模型、PC 控制、取指通道
- 通过 DPI 内存读写测试

### Phase 1：顺序核 — 从零到 Coremark（2024.10.26 - 2024.11.12）

这是最艰苦的阶段，从无到有把一个顺序核搭起来。

- **10.26 - 10.29**：完成 EXU（ALU/BJU）、Decoder、RegFile、IBuffer
- **11.03 - 11.04**：接入 difftest，通过第一条指令
- **11.04 - 11.09**：密集 debug 阶段
  - 修复大量译码错误（I-type 立即数符号扩展、func7/func3 解码）
  - 实现 ALU Forwarding（数据前递）
  - 修复 Load/Store 相关 bug（mask、bypass、sign extend）
  - 修复 FIFO 同时读写计数错误
  - 加入 Mem Stall 逻辑、重定向处理
  - 加入 64B 非对齐取指处理
- **11.10 - 11.11**：修复 MMIO、redirect 与正常握手冲突
- **11.12**：**通过 Coremark 10 次迭代！** 🎉 → `trinity_v0.5_241112`

### Phase 2：总线重构 + Cache（2024.11.13 - 2025.01.14）

- **11.13 - 11.26**：后端重构，修 MMIO bug，FSM 优化，修组合环路
- **12.13 - 12.17**：Trinity 总线重构，开始写 DCache
- **01.05 - 01.06**：ICache 实现，修复 Cache index 查找错误
- **01.07 - 01.14**：Arbitor 重写，DCache 握手同步化，ICache 从 2-wide 扩展到 4-wide 取指，大量信号重命名规范化

### Phase 3：分支预测（2025.01.15 - 2025.01.17）

- **01.15**：加入 BPU（BHT + BTB），指令管理逻辑
- **01.16**：预测结果流水线传递，BJU Scoreboard，PMU 统计
- **01.17**：Verilator 兼容性修复（`fuck verilator` 就是在修 BHT 数组索引问题）

### Phase 4：乱序改造（2025.01.20 - 2025.02.08）

这是工作量最大的阶段，把顺序核改造成乱序双发射。

- **01.20 - 01.26**：
  - 设计并实现 ROB（Shattered ROB 方式）、Freelist、SpecRAT、ArchRAT
  - 实现 Rollback/Walk 逻辑
  - 设计 Age-based Issue Queue
  - 加入 Circular Queue 模板
- **01.27 - 01.31**：
  - 实现 Dispatch 逻辑（IQ + SQ + ROB 三路入队）
  - 后端模块化重构（IDU/IRU/ISU/EXU 各自 wrapper）
  - 加入 Mem Issue Queue
  - 预测信息传递到后端
- **02.01 - 02.04**：
  - 乱序 core_top 集成
  - 前端/后端流水线对接
  - 密集 debug：SpecRAT bypass、ROB flush、Age Policy oldest 逻辑
- **02.05 - 02.07**：
  - 加入 Store Queue、DCache Arbiter
  - 实现 Load-to-Store Forwarding
  - **02.07 通过 Coremark（2 次迭代）** → `trinity_v2.0_250208` 预备
- **02.08**：加入 OOO Age Policy、Freelist 修复、PMU 统计 → **`trinity_v2.0_250208` tag**

### Phase 5：打磨稳定（2025.02.10 - 2025.03.29）

- Cache victim 选择优化
- 分支预测 PMU 统计（btype + jtype 分开统计）
- IBuffer FIFO 满逻辑修复
- Freelist 冗余代码清理

→ **`trinity_v2.1_250329`** — 最后一个稳定版本，difftest 全部通过

### Phase 6：LoadPipe 重构（2025.07.19 - 2025.07.28）— 未完成

- 尝试重构 LoadPipe 为多级流水
- 加入 MSHR（Miss Status Holding Register）
- 代码写到一半未完成，接口未对齐，**编译不过**

## 仿真环境

### 依赖

| 工具 | 版本要求 | 用途 |
|------|----------|------|
| **Verilator** | 5.0+ | Verilog → C++ 编译 |
| **g++** | 支持 C++17 | 编译 C++ 仿真代码 |
| **libzstd-dev** | — | 波形压缩（FST 格式） |
| **GTkWave** | — | 波形查看（可选） |
| **git** | — | 拉取代码和 submodule |

### 第一步：安装依赖（Ubuntu 22.04）

```bash
# 基础编译工具
sudo apt install -y git g++ make autoconf flex bison ccache \
  libfl2 libfl-dev zlib1g zlib1g-dev libzstd-dev

# GTKWave（可选，看波形用）
sudo apt install -y gtkwave

# 安装 Verilator 5.x（apt 默认版本太旧，需要从源码编译）
cd ~
git clone --depth 1 --branch v5.026 https://github.com/verilator/verilator verilator_src
# 如果 GitHub clone 报 HTTP/2 错误，先执行：git config --global http.version HTTP/1.1
cd verilator_src
autoconf
./configure
make -j$(nproc)
sudo make install
verilator --version  # 验证：应显示 Verilator 5.026
```

### 第二步：克隆项目

```bash
# 克隆主仓库
git clone https://github.com/<your-username>/trinity.git
cd trinity

# 拉取 difftest submodule（必需！）
git submodule update --init --recursive
```

### 第三步：切换到稳定版本（重要！）

main 分支的最新代码包含未完成的 LoadPipe 重构，**编译不过**。需要切到稳定版本：

```bash
# 切到 v2.1（最后一个稳定版本，difftest 全通过）
git checkout trinity_v2.1_250329
```

### 第四步：编译仿真器

```bash
# 设置环境变量（NOOP_HOME 必须指向项目根目录）
export NOOP_HOME=$(pwd)

# 编译（这一步会先用 Verilator 把 Verilog 编译成 C++，再用 g++ 编译链接）
# 大约需要 1-3 分钟
make diff
```

编译成功后会在 `build/` 下生成 `emu` 可执行文件（约 4.5MB）。

**常见编译问题：**
- `verilator not found` → Verilator 没装好或不在 PATH 里
- `zstd.h: No such file` → `sudo apt install libzstd-dev`
- `Cannot find module 'xxx'` → 你可能在 main 分支上，先 `git checkout trinity_v2.1_250329`

### 第五步：运行仿真

```bash
# 方式一：用 Makefile 一键跑（coremark 2 次迭代，默认参数）
make run_diff

# 方式二：手动指定参数运行
./build/emu \
  --diff=$NOOP_HOME/r2r/tri-riscv64-nemu-interpreter-so \
  -b 0 -e 241022 \
  --image=$NOOP_HOME/r2r/cmark/coremark-riscv64-nutshell-2.bin

# 运行 coremark 10 次迭代（长时间仿真）
./build/emu \
  --diff=$NOOP_HOME/r2r/tri-riscv64-nemu-interpreter-so \
  -b 0 -e 241022 \
  --image=$NOOP_HOME/r2r/cmark/coremark-riscv64-nutshell-10.bin

# 只跑 N 条指令后停止（用于快速验证）
./build/emu \
  --diff=$NOOP_HOME/r2r/tri-riscv64-nemu-interpreter-so \
  -b 0 -e 1000 \
  --image=$NOOP_HOME/r2r/cmark/coremark-riscv64-nutshell-2.bin
```

**参数说明：**
- `--diff=...`：指定 NEMU 参考模型动态库（必需）
- `--image=...`：指定要加载的 RISC-V 程序（.bin 文件）
- `-b`：起始指令编号（一般设 0）
- `-e`：最大仿真指令数（防止死循环跑不完）

### 第六步：查看结果

**成功输出示例：**
```
HIT GOOD TRAP at pc = 0x000000008000249c
host time spent = 240601 us
total guest instructions = 732676
simulation frequency = 3045191 instr/s
```

看到 `HIT GOOD TRAP` = 仿真通过，CPU 行为与 NEMU 完全一致。

看到 `FAILED` 或直接 crash = 有 bug，需要看波形 debug。

### 查看波形（debug 用）

```bash
# 运行仿真并 dump 波形（FST 格式）
./build/emu \
  --diff=$NOOP_HOME/r2r/tri-riscv64-nemu-interpreter-so \
  --dump-wave-full \
  --wave-path=./dump/sim.fst \
  -b 0 -e 1000 \
  --image=$NOOP_HOME/r2r/cmark/coremark-riscv64-nutshell-2.bin

# 用 GTKWave 打开波形
gtkwave ./dump/sim.fst
```

### 清理

```bash
# 清理编译产物（保留 emu）
make clean

# 彻底清理（包括 Verilator 生成的 C++ 代码）
rm -rf build/emu-compile obj_dir
```

### 仿真原理

- **DUT**：trinity CPU，由 Verilator 从 Verilog 编译成 C++，再由 g++ 编译为可执行文件
- **REF**：NEMU（南京大学 RISC-V 模拟器），作为参考模型，每条指令的行为一定正确
- **Difftest**：每个时钟周期对比 DUT 和 REF 的 PC、寄存器、内存，不一致立刻报错停机
- **simddr**：模拟 DDR 内存，程序 .bin 文件加载到 0x80000000 起始地址

### 性能数据（v2.1，coremark 2 次迭代）

- 仿真速度：~3M instr/s
- 总指令数：732,676 条
- 分支预测准确率：branch 92.07%，jump 92.36%
- IntISQ PMU：block_enq 131 cycles，can_issue 112,326 times

## Tags

| Tag | 日期 | Commit | 描述 |
|-----|------|--------|------|
| `trinity_v0.5_241112` | 2024-11-12 | `3978c04` | 顺序核 pass coremark 10 iters |
| `trinity_v1.0_241126` | 2024-11-26 | — | 后端重构 + FSM 优化 |
| `trinity_v1.3_250112` | 2025-01-12 | — | Cache 大量 bug fix |
| `trinity_v1.5_250117` | 2025-01-17 | — | 分支预测（BHT + BTB）|
| `trinity_v2.0_250208` | 2025-02-08 | `1bcf928` | 乱序双发射 + PMU |
| `trinity_v2.1_250329` | 2025-03-29 | `fc35caa` | 最终稳定版，difftest 全通过 |

## 致谢

- [香山（XiangShan）Difftest 框架](https://github.com/OpenXiangShan/difftest) — 仿真验证框架
- [NEMU](https://github.com/NJU-ProjectN/nemu) — RISC-V 参考模型
- [NutShell](https://github.com/OSCPU/NutShell) — Coremark 测试程序来源

---

*Trinity: core / interlink / AI*
