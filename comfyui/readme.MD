here is the commands used on imagebeast:

PS C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI> C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

=============================================
  ComfyUI Custom Nodes Inventory
  Host : IMAGEBEAST
  Root : .
=============================================

Found 46 custom node(s):

  1. .disabled
  2. __pycache__
  3. cocotools_io
  .
  .
  .
 42. panorama-stickers
 43. rgthree-comfy
 44. Vantage-DreamOmni2
 45. was-ns
 46. zhihui_nodes_comfyui

Total: 46 custom nodes

Saved: .\comfy-reports\IMAGEBEAST-CustomNodes-2026-04-07_0954.txt





PS C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI> C:\repos\scripts\comfyui\Get-Models.ps1 C:\ComfyUI_Models\

=============================================
  ComfyUI Models Inventory
  Host : IMAGEBEAST
  Root : C:\ComfyUI_Models\
=============================================

Scanning models...
This error can be ignored:
Get-ChildItem : Access to the path 'C:\ComfyUI_Models\models\dreamomni2\.cache' is denied.
At C:\repos\scripts\comfyui\Get-Models.ps1:38 char:13
+ $allFiles = Get-ChildItem -Path $modelsPath -File -Recurse |
+             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : PermissionDenied: (C:\ComfyUI_Mode...eamomni2\.cache:String) [Get-ChildItem], Unauthoriz
   edAccessException
    + FullyQualifiedErrorId : DirUnauthorizedAccessError,Microsoft.PowerShell.Commands.GetChildItemCommand

Found 147 model file(s)

  checkpoints                    14 file(s)    112.71 GB
  clip                            1 file(s)      0.80 GB
  clip_vision                     5 file(s)     15.25 GB
  controlnet                      4 file(s)      3.37 GB
.
.
.
  pulid                           1 file(s)      1.06 GB
  RMBG                            1 file(s)      0.82 GB
  sams                            1 file(s)      0.35 GB
  text_encoders                  15 file(s)     86.04 GB
  ultralytics                     4 file(s)      0.13 GB
  unet                            3 file(s)     44.32 GB
  upscale_models                  3 file(s)      0.19 GB
  vae                             5 file(s)      1.49 GB
  vae_approx                      8 file(s)      0.02 GB

  TOTAL                         147 file(s)    613.25 GB

Saved: .\comfy-reports\IMAGEBEAST-Models-2026-04-07_0958.csv







PS C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI> C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 -ModelsPath C:\ComfyUI_Models\ -WorkflowDir .\user\default\workflows\



=============================================
  ComfyUI Workflow -> Model Map
  Host      : IMAGEBEAST
  ComfyRoot : C:\ComfyUI_easy\ComfyUI-Easy-Install\comfyui
  Workflows : .\user\default\workflows\
  Models    : C:\ComfyUI_Models\
=============================================

Building model inventory...
Get-ChildItem : Access to the path 'C:\ComfyUI_Models\models\dreamomni2\.cache' is denied.
At C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1:65 char:1
+ Get-ChildItem -Path $modelsPath -File -Recurse |
+ ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    + CategoryInfo          : PermissionDenied: (C:\ComfyUI_Mode...eamomni2\.cache:String) [Get-ChildItem], Unauthoriz
   edAccessException
    + FullyQualifiedErrorId : DirUnauthorizedAccessError,Microsoft.PowerShell.Commands.GetChildItemCommand

  Found 147 model file(s) on disk
Scanning workflow files in: .\user\default\workflows\
  Found 353 workflow file(s)

  SKIP (bad JSON): FaceLock.json
  SKIP (bad JSON): pluid_fluid_test4.json
  SKIP (bad JSON): pluid_fluid_test5.json
  SKIP (bad JSON): img2img.json
  Processed : 302 workflow(s)
  Skipped   : 51 (no model refs or unreadable)

--- Model Usage Summary (top 20) ---

model_filename                              model_category model_size_gb workflow_count
--------------                              -------------- ------------- --------------
flux2-vae.safetensors                       models                 0.313             70
ae.safetensors                              models                 0.313             67
clip_l.safetensors                          models                 0.229             50
qwen_3_4b.safetensors                       models                 7.492             47
dreamshaper_8.safetensors                   models                 1.986             36
flux-2-klein-4b-fp8.safetensors             models                 3.791             33
qwen_3_8b_fp8mixed.safetensors              models                  8.07             31
t5xxl_fp16.safetensors                      models                 9.116             29
flux1-dev-fp8.safetensors                   models                16.062             28
sd_xl_base_1.0.safetensors                  models                 6.462             22
flux-2-klein-9b-fp8mixed.safetensors        models                 8.785             17
flux-outpaint-lora.safetensors              models                 0.071             15
t5xxl_fp8_e4m3fn.safetensors                models                 4.558             15
pulid_flux_v0.9.1.safetensors               models                 1.064             15
z_image_turbo_bf16.safetensors              models                11.464             13
flux-2-klein-9b-kv-fp8.safetensors          models                 9.145             12
qwen_2.5_vl_7b_fp8_scaled.safetensors       models                  8.74             10
CLIP-ViT-H-14-laion2B-s32B-b79K.safetensors models                 3.436             10
qwen_image_vae.safetensors                  models                 0.236             10
z-image-turbo-fp8-aio.safetensors           models                 9.635              8



--- Missing Models (referenced but NOT on disk): 229 ---

model_ref                                                 workflow_file
---------                                                 -------------
4x_foolhardy_Remacri.pth                                  C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
4x_foolhardy_Remacri.pth                                  C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
4x-AnimeSharp.pth                                         C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
4xFaceUpDAT.pth                                           C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
4xFaceUpDAT.pth                                           C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
aziibpixelmix_v10.safetensors                             C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
bopbtl\detection\FT_Epoch_latest.pt                       C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
bopbtl\mapping_Patch_Attention\latest_net_mapping_net.pth C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
bopbtl\VAE_A_quality\latest_net_G.pth                     C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...
bopbtl\VAE_B_scratch\latest_net_G.pth                     C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI\user\default\...



--- Unused Models (on disk but NEVER referenced): 70 ---

filename                                 category size_gb
--------                                 -------- -------
Aether_Cloud_v1.safetensors              models     0.634
Aether_Fire_v1_SDXL_LoRA.safetensors     models     0.634
appearance_feature_extractor.safetensors models     0.003
blindbox_v1_mix.safetensors              models     0.141
Caricatures_V2-000007.safetensors        models     0.425
chahua.safetensors                       models     0.159
claymation_000000384.safetensors         models      0.04
claymation-000012.safetensors            models     0.018
clip_g.safetensors                       models     1.294
Coloring_book_-_LineArt.safetensors      models     0.213



Output files:
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-full_map.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-model_usage.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-unused_models.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-missing_models.csv
  .\comfy-reports\IMAGEBEAST-WorkflowMap-2026-04-07_1101-summary.txt

Done!



========
tl/dr
========


here is the commands used on imagebeast:

PS C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI> C:\repos\scripts\comfyui\Get-CustomNodes.ps1 .

PS C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI> C:\repos\scripts\comfyui\Get-Models.ps1 C:\ComfyUI_Models\

PS C:\ComfyUI_easy\ComfyUI-Easy-Install\ComfyUI> C:\repos\scripts\comfyui\Get-WorkflowModelMap.ps1 -ModelsPath C:\ComfyUI_Models\ -WorkflowDir .\user\default\workflows\



UPDATE, new format:

.\Get-Models.ps1 -ModelsPath "C:\Users\DrDen\OneDrive\DropBoxReplacement\MathesDropBox\0ComfyUI\Models_bare"

