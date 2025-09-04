# zsh-filepg

**Progress-bar enhanced `cp`/`mv`/`rm` for zsh**  

A set of user-friendly file operations with **progress bar**, **preview mode**, **exclude patterns**, **sudo auto-escalation**, and **tab completion** etc,.

Completely programmed by AI tools, thanks to 🎉Kimi(Moonshot) ChatGPT(OpenAI) Claude(Anthropic) Gemini(Google) Qwen(Alibaba)🎉

⚠️Note: Since all codes are written by AI, please use them at your own risk. It is strongly recommended to use -t to preview the operation effect.

## ✨ Features:
- 📊 Real-time progress (size, ETA)
- 🔍 `-t` / `--test` dry-run mode
- 🚫 `--x="*.tmp logs/"` exclude with glob patterns
- 🔐 Auto `sudo` for protected files
- 💡 `rmpg` asks for confirmation before deletion
- 🧩 `--x=` supports tab completion
- 🍎 macOS & Linux compatible

## 📦 Install

### Option 1: cURL (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/2O48/zsh-filepg/main/install.sh | sh
```

Then restart your terminal or run:

```bash
source ~/.zshrc
```

### Option 2: wget

```bash
wget -qO- https://raw.githubusercontent.com/2O48/zsh-filepg/main/install.sh | sh
```

### Option 3: Manual Install

```bash
mkdir -p ~/.zsh-filepg
curl -fsSL https://raw.githubusercontent.com/2O48/zsh-filepg/main/filepg.zsh -o ~/.zsh-filepg/filepg.zsh
echo 'source ~/.zsh-filepg/filepg.zsh' >> ~/.zshrc
source ~/.zsh-filepg/filepg.zsh
```

### Option 4: Oh My Zsh Plugin (Recommended for OMZ users)

```bash
git clone https://github.com/2O48/zsh-filepg ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-filepg
```

Edit `~/.zshrc` and add to plugins:

```zsh
plugins=(... zsh-filepg)
```

Then reload:

```bash
source ~/.zshrc
```

## 🧪 Usage

1. **⌛ Progress bar with size and time**: Shows real-time progress including processed/total size and ETA during copy, move, or delete operations.  
   Example:
   ```zsh
   % cppg test/*.mp4 videos
   [================================================== ] 100% 45M/45M ETA 00:00:00
   ```

2. **👁️ Preview with `-t`**: Add `-t` or `--test` to preview the operation, including each file/directory and its size, without executing it.  
   Example:
   ```zsh
   % mvpg -t videos/*.mp4 test
   Will Move the following:
   (File) videos/desert_00001.mp4 -> test (1M)
   (File) videos/desert_00005.mp4 -> test (1M)
   Total: 2M
   ```

3. **🤚 Exclude with `--x`**: Use `--x` to exclude files/directories. Supports tab completion and wildcards like `*`, `?`.  
   Example:
   ```zsh
   % rmpg --x=videos/desert* videos/*.mp4
   Will Delete the following:
   (file) videos/highspeed20_00002.mp4 (950K)
   (file) videos/highspeed20_00028.mp4 (1M)
   (file) videos/highspeed20_00041.mp4 (1M)
   Total: 3M
   Confirm deletion? [y/N]:
   ```

4. **👑 Auto sudo escalation**: Automatically requests root privileges when operating on files/directories requiring `sudo`.

5. **🫂 Cross-platform compatibility**: Fully compatible with both 🐧Linux and 🍎macOS.

6. **⚠️ Confirmation before deletion**: Runs a preview (like `-t`) before deletion, showing all files to be removed, and waits for user confirmation before proceeding.
   Example:
   ```zsh
   % rmpg videos/*.mp4
   Will Delete the following:
   (file) videos/desert_00001.mp4 (1M)
   (file) videos/desert_00005.mp4 (1M)
   (file) videos/highspeed20_00002.mp4 (950K)
   (file) videos/highspeed20_00028.mp4 (1M)
   (file) videos/highspeed20_00041.mp4 (1M)
   Total: 5M
   Confirm deletion? [y/N]:
   ```

## 🤝 Contribute

PRs and issues welcome!

## 📄 License

⚖️ MIT
