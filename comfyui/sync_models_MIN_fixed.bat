@echo off
REM ============================================================
REM  sync_models_MIN  -- Safe for 8GB VRAM
REM  32 files each <= 8GB, all safe for RTX 5060
REM  32 files  |  64.76 GB
REM  Run this on IMAGEBEAST
REM  Source root : C:\ComfyUI_Models\models
REM  Dest root   : C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare
REM  Preserves full subdir structure - ComfyUI will find the models
REM  OneDrive syncs automatically to TravelBeast + ChatWorkhorse
REM ============================================================

REM --- checkpoints ---
REM   6.86 GB  [6 wf]  hunyuan_3d_v2.1.safetensors
REM   1.99 GB  [9 wf]  realisticVisionV51_v51VAE.safetensors
robocopy "C:\ComfyUI_Models\models\checkpoints" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\checkpoints" "realisticVisionV51_v51VAE.safetensors" "hunyuan_3d_v2.1.safetensors" /COPY:DAT /R:2 /W:5

REM --- checkpoints\SD1.5 ---
REM   1.99 GB  [26 wf]  dreamshaper_8.safetensors
REM   1.99 GB  [6 wf]  juggernaut_reborn.safetensors
robocopy "C:\ComfyUI_Models\models\checkpoints\SD1.5" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\checkpoints\SD1.5" "dreamshaper_8.safetensors" "juggernaut_reborn.safetensors" /COPY:DAT /R:2 /W:5

REM --- checkpoints\SD3 ---
REM   4.04 GB  [3 wf]  sd3_medium.safetensors
robocopy "C:\ComfyUI_Models\models\checkpoints\SD3" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\checkpoints\SD3" "sd3_medium.safetensors" /COPY:DAT /R:2 /W:5

REM --- checkpoints\SDXL ---
REM   6.62 GB  [19 wf]  Juggernaut_X_RunDiffusion.safetensors
REM   6.46 GB  [32 wf]  albedobaseXL_v21.safetensors
REM   6.46 GB  [45 wf]  sd_xl_base_1.0.safetensors
robocopy "C:\ComfyUI_Models\models\checkpoints\SDXL" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\checkpoints\SDXL" "sd_xl_base_1.0.safetensors" "albedobaseXL_v21.safetensors" "Juggernaut_X_RunDiffusion.safetensors" /COPY:DAT /R:2 /W:5

REM --- clip ---
REM   0.80 GB  [4 wf]  EVA02_CLIP_L_336_psz14_s6B.pt
robocopy "C:\ComfyUI_Models\models\clip" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\clip" "EVA02_CLIP_L_336_psz14_s6B.pt" /COPY:DAT /R:2 /W:5

REM --- clip_vision ---
REM   3.44 GB  [39 wf]  CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors
REM   3.67 GB  [11 wf]  CLIP-ViT-H-14-openclip.safetensors
robocopy "C:\ComfyUI_Models\models\clip_vision" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\clip_vision" "CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors" "CLIP-ViT-H-14-openclip.safetensors" /COPY:DAT /R:2 /W:5

REM --- controlnet ---
REM   1.35 GB  [5 wf]  control_v11f1p_sd15_depth.pth
robocopy "C:\ComfyUI_Models\models\controlnet" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\controlnet" "control_v11f1p_sd15_depth.pth" /COPY:DAT /R:2 /W:5

REM --- controlnet\sd1.5 ---
REM   0.67 GB  [3 wf]  control_v11p_sd15_canny_fp16.safetensors
REM   0.67 GB  [4 wf]  control_v11p_sd15_openpose_fp16.safetensors
robocopy "C:\ComfyUI_Models\models\controlnet\sd1.5" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\controlnet\sd1.5" "control_v11p_sd15_openpose_fp16.safetensors" "control_v11p_sd15_canny_fp16.safetensors" /COPY:DAT /R:2 /W:5

REM --- ipadapter ---
REM   1.00 GB  [30 wf]  ip-adapter-faceid_sdxl.bin
robocopy "C:\ComfyUI_Models\models\ipadapter" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\ipadapter" "ip-adapter-faceid_sdxl.bin" /COPY:DAT /R:2 /W:5

REM --- ipadapter - Copy ---
REM   1.39 GB  [6 wf]  ip-adapter-faceid-plusv2_sdxl.bin
robocopy "C:\ComfyUI_Models\models\ipadapter - Copy" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\ipadapter - Copy" "ip-adapter-faceid-plusv2_sdxl.bin" /COPY:DAT /R:2 /W:5

REM --- loras\FLUX ---
REM   0.65 GB  [14 wf]  FLUX.1-Turbo-Alpha.safetensors
REM   0.57 GB  [13 wf]  Master-Claymation.safetensors
REM   1.34 GB  [14 wf]  dreamomni2_edit_lora.safetensors
REM   1.34 GB  [14 wf]  dreamomni2_gen_lora.safetensors
robocopy "C:\ComfyUI_Models\models\loras\FLUX" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\loras\FLUX" "FLUX.1-Turbo-Alpha.safetensors" "dreamomni2_gen_lora.safetensors" "dreamomni2_edit_lora.safetensors" "Master-Claymation.safetensors" /COPY:DAT /R:2 /W:5

REM --- loras\FLUX2 ---
REM   0.36 GB  [3 wf]  flux2_berthe_morisot.safetensors
robocopy "C:\ComfyUI_Models\models\loras\FLUX2" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\loras\FLUX2" "flux2_berthe_morisot.safetensors" /COPY:DAT /R:2 /W:5

REM --- loras\Qwen Image Edit 2511 ---
REM   0.79 GB  [47 wf]  Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors
robocopy "C:\ComfyUI_Models\models\loras\Qwen Image Edit 2511" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\loras\Qwen Image Edit 2511" "Qwen-Image-Edit-2511-Lightning-4steps-V1.0-bf16.safetensors" /COPY:DAT /R:2 /W:5

REM --- loras\Qwen2509 ---
REM   1.58 GB  [9 wf]  Qwen-Image-Lightning-4steps-V2.0.safetensors
robocopy "C:\ComfyUI_Models\models\loras\Qwen2509" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\loras\Qwen2509" "Qwen-Image-Lightning-4steps-V2.0.safetensors" /COPY:DAT /R:2 /W:5

REM --- loras\SDXL ---
REM   0.85 GB  [40 wf]  CLAYMATE_V2.03_.safetensors
REM   0.42 GB  [5 wf]  Caricatures_V2-000007.safetensors
robocopy "C:\ComfyUI_Models\models\loras\SDXL" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\loras\SDXL" "CLAYMATE_V2.03_.safetensors" "Caricatures_V2-000007.safetensors" /COPY:DAT /R:2 /W:5

REM --- loras\Z-Image ---
REM   0.04 GB  [4 wf]  claymation_000000384.safetensors
robocopy "C:\ComfyUI_Models\models\loras\Z-Image" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\loras\Z-Image" "claymation_000000384.safetensors" /COPY:DAT /R:2 /W:5

REM --- pulid ---
REM   1.06 GB  [16 wf]  pulid_flux_v0.9.1.safetensors
robocopy "C:\ComfyUI_Models\models\pulid" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\pulid" "pulid_flux_v0.9.1.safetensors" /COPY:DAT /R:2 /W:5

REM --- text_encoders\FLUX_Fill ---
REM   4.71 GB  [3 wf]  t5-v1_1-xxl-encoder-Q8_0.gguf
robocopy "C:\ComfyUI_Models\models\text_encoders\FLUX_Fill" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\FLUX_Fill" "t5-v1_1-xxl-encoder-Q8_0.gguf" /COPY:DAT /R:2 /W:5

REM --- text_encoders\SD3 ---
REM   1.29 GB  [3 wf]  clip_g.safetensors
robocopy "C:\ComfyUI_Models\models\text_encoders\SD3" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\text_encoders\SD3" "clip_g.safetensors" /COPY:DAT /R:2 /W:5

REM --- upscale_models ---
REM   0.06 GB  [5 wf]  4x-UltraSharp.pth
REM   0.06 GB  [6 wf]  4x_NMKD-Siax_200k.pth
robocopy "C:\ComfyUI_Models\models\upscale_models" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\upscale_models" "4x_NMKD-Siax_200k.pth" "4x-UltraSharp.pth" /COPY:DAT /R:2 /W:5

REM --- vae\Qwen2509 ---
REM   0.24 GB  [128 wf]  qwen_image_vae.safetensors
robocopy "C:\ComfyUI_Models\models\vae\Qwen2509" "C:\Users\Pc\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare\vae\Qwen2509" "qwen_image_vae.safetensors" /COPY:DAT /R:2 /W:5

echo.
echo ============================================================
echo  sync_models_MIN  -- Safe for 8GB VRAM  -- COMPLETE
echo  32 files  (64.76 GB)
echo  OneDrive will sync to TravelBeast and ChatWorkhorse
echo ============================================================
pause
