# Gênny & Sophie Studio — motor local A55

Target: Galaxy A55 5G / 8 GB RAM. Sem API paga.

## Decisão do motor
- Runtime: stable-diffusion.cpp através da integração Android/Local Diffusion.
- Modelo inicial: Stable Diffusion 1.5, 512x512.
- Optimização: quantização Q4_0, Flash Attention e VAE tiling.
- O utilizador NÃO deve escolher ficheiros, quantização, CFG, sampler ou backend.
- O app deve preparar/descarregar o modelo automaticamente no primeiro arranque e validar checksum antes de o activar.
- A interface final expõe apenas personagem (Gênny/Sophie/ambas), referência, texto/voz e Criar.

## Critério de entrega
Não considerar funcional enquanto o fluxo completo não produzir uma imagem:
abrir app -> motor preparado -> comando -> geração -> imagem visível/salva.

## Próxima implementação
Substituir a importação manual de ModelManager por ModelInstaller com download retomável, progresso, espaço livre, checksum e estado READY/ERROR. Depois ligar o runtime nativo ao botão Criar.
