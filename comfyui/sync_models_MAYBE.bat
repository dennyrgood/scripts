@echo off
REM ============================================================
REM  sync_models_MAYBE -- Marginal models only (8-12GB each)
REM  Run AFTER sync_models_MIN.bat
REM  6 files  |  59.34 GB
REM  Run this on IMAGEBEAST
REM  Source root : C:\ComfyUI_Models\models
REM  Dest root   : C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare
REM  These may work on RTX 5060 8GB with offloading - test before travelling
REM  OneDrive syncs automatically to TravelBeast + ChatWorkhorse
REM ============================================================

REM --- checkpoints\Z-image ---
REM   9.63 GB  [9 wf]  z-image-turbo-fp8-aio.safetensors
robocopy "C:\ComfyUI_Models\models\checkpoints\Z-image" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\checkpoints\Z-image" "z-image-turbo-fp8-aio.safetensors" /COPYALL /R:2 /W:5

REM --- diffusion_models\FLUX1_Kontext ---
REM   11.08 GB  [14 wf]  flux1-kontext-dev-fp8-e4m3fn.safetensors
robocopy "C:\ComfyUI_Models\models\diffusion_models\FLUX1_Kontext" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\diffusion_models\FLUX1_Kontext" "flux1-kontext-dev-fp8-e4m3fn.safetensors" /COPYALL /R:2 /W:5

REM --- diffusion_models\FLUX2 ---
REM   8.91 GB  [7 wf]  flux-2-klein-base-9b-fp8.safetensors
robocopy "C:\ComfyUI_Models\models\diffusion_models\FLUX2" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\diffusion_models\FLUX2" "flux-2-klein-base-9b-fp8.safetensors" /COPYALL /R:2 /W:5

REM --- text_encoders\FLUX_Fill ---
REM   9.12 GB  [112 wf]  t5xxl_fp16.safetensors
robocopy "C:\ComfyUI_Models\models\text_encoders\FLUX_Fill" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\FLUX_Fill" "t5xxl_fp16.safetensors" /COPYALL /R:2 /W:5

REM --- text_encoders\Qwen2509 ---
REM   8.74 GB  [128 wf]  qwen_2.5_vl_7b_fp8_scaled.safetensors
robocopy "C:\ComfyUI_Models\models\text_encoders\Qwen2509" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\Qwen2509" "qwen_2.5_vl_7b_fp8_scaled.safetensors" /COPYALL /R:2 /W:5

REM --- unet ---
REM   11.85 GB  [6 wf]  flux1-fill-dev-Q8_0.gguf
robocopy "C:\ComfyUI_Models\models\unet" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\unet" "flux1-fill-dev-Q8_0.gguf" /COPYALL /R:2 /W:5

echo.
echo ============================================================
echo  sync_models_MAYBE -- COMPLETE
echo  6 files  (59.34 GB)
echo  OneDrive will sync to TravelBeast and ChatWorkhorse
echo ============================================================
pause
