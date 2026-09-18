# Motor local do Studio

O APK integrado é construído por [a55-local-diffusion.yml](.github/workflows/a55-local-diffusion.yml). Usa o motor de [Local Diffusion](https://github.com/rmatif/Local-Diffusion) e o checkpoint público de [Stable Diffusion 1.5](https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-v1-5/blob/main/v1-5-pruned-emaonly.safetensors).

No primeiro arranque, o próprio app descarrega aproximadamente 4,3 GB, retoma transferências interrompidas e verifica o SHA-256 antes de criar imagens. A geração posterior é local, a 512 × 512, com quantização Q4_0 no carregamento e execução CPU.

**Verificação pendente:** o CI comprova que o APK compila e contém o motor nativo. Ainda é preciso testar a transferência do modelo e uma imagem concluída num Galaxy A55 real; a seleção da personagem por nome e img2img não garantem a identidade facial canónica.
