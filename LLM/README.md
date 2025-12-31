# LLM Resources Directory

This directory is for storing the local LLM model files and binaries required for AI features.

## Required Files

1. **llama-cli** - The LLM inference binary
2. **Model file** - A Qwen2.5 model in GGUF format (e.g., `qwen2.5-7b-instruct.gguf`)

## Setup Instructions

### Download llama-cli

- **For Apple Silicon (M1/M2/M3)**: 
  - Download from [llama.cpp releases](https://github.com/ggerganov/llama.cpp/releases)
  - Look for `llama-cli` or `llama-cli-macos-arm64` in the latest release
  - Or build from source: [llama.cpp repository](https://github.com/ggerganov/llama.cpp)

- **For Intel Macs**: 
  - Download `llama-cli-macos-x64` from the releases page

### Download Qwen2.5 Model

Download a compatible Qwen2.5 model in GGUF format:

- **Recommended**: Qwen2.5-7B-Instruct-GGUF (around 4-5GB)
- **Download sources**:
  - [Hugging Face - Qwen2.5 Models](https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF)
  - [TheBloke's Qwen2.5 Models](https://huggingface.co/TheBloke)
  - Look for files ending in `.gguf` format

**Model size recommendations**:
- **7B model**: Good balance of quality and speed (~4-5GB)
- **3B model**: Faster but lower quality (~2GB)
- **14B+ model**: Higher quality but slower (~8GB+)

### Installation Steps

1. Copy `llama-cli` binary to this directory:
   ```bash
   cp /path/to/llama-cli LLM/
   chmod +x LLM/llama-cli
   ```

2. Copy the model file to this directory:
   ```bash
   cp /path/to/qwen2.5-7b-instruct.gguf LLM/
   ```

3. Verify the files are in place:
   ```bash
   ls -lh LLM/
   ```

4. When you build the app with `./build_app.sh`, these files will be automatically copied into the app bundle.

## File Structure

After setup, your `LLM/` directory should look like:
```
LLM/
├── llama-cli          # Executable binary
├── qwen2.5-*.gguf     # Model file (name may vary)
└── README.md          # This file
```

## Troubleshooting

- **Permission denied**: Make sure `llama-cli` is executable (`chmod +x LLM/llama-cli`)
- **Model not found**: Check that the model file is in `.gguf` format and placed in this directory
- **AI features not working**: Verify the model file name matches what the app expects, or check the console logs for errors

## Note

The LLM files are not included in the git repository due to their large size. Each user needs to download and place them manually.
