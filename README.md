# Hide-It 1.0

Um aplicativo gratuito para organizar a barra de menus do macOS. Arraste os ícones que deseja ocultar para a esquerda do divisor e use a seta para mostrá-los ou ocultá-los.

## Requisitos

- macOS 13 ou posterior.
- Command Line Tools da Apple e Swift 5.9 ou posterior para compilar.
- No macOS 27, permissão de Acessibilidade e o aplicativo instalado em `/Applications`.

## Compilar no Mac

1. Instale as Command Line Tools da Apple com `xcode-select --install`.
2. No Terminal, entre na pasta do projeto e execute `bash build.command`.
3. Copie `dist/Hide-It.app` para a pasta Aplicativos e abra-o.

Para gerar o instalador, execute `bash build-installer.command`. O arquivo `dist/Hide-It-Instalador.pkg` instala o aplicativo em Aplicativos, substitui uma cópia anterior e fecha o Hide-It instalado se ele estiver aberto. O instalador pode solicitar a senha de administrador.

O script compila para a arquitetura do Mac utilizado, sem dependências externas. O aplicativo recebe assinatura ad hoc; o pacote não é assinado com Developer ID nem notarizado. O macOS pode impedir sua abertura em outros computadores.

## Usar

Segure Command e arraste os ícones que deseja ocultar para a esquerda do divisor `│`. Deixe a seta do Hide-It à direita dele. Clique na seta para alternar a visibilidade e use o clique direito para abrir as opções. Ao manter Command pressionado, a barra alterna a cada 3 segundos. Se a opção de recolhimento automático estiver ativada, ela se recolhe após 10 segundos expandida. Para desinstalar, feche o Hide-It e remova o aplicativo.

No macOS 27, o Hide-It usa Acessibilidade para identificar os aplicativos à esquerda do divisor e uma interface interna do macOS para ocultá-los. É preciso autorizar o Hide-It em Ajustes do Sistema. A interface interna pode mudar em atualizações do macOS. Ícones do sistema permanecem visíveis, e vários ícones do mesmo aplicativo são tratados juntos. O aplicativo não envia esses dados pela rede.

## Estado desta entrega

Implementação em Swift/AppKit compilada no macOS. A ocultação usa uma interface interna no macOS 27 e ainda precisa ser verificada com monitores múltiplos, notch e alterações de resolução. Não inclui zona permanentemente oculta nem painel separado para ícones.

## Verificação no Mac

- Compilar e abrir sem erros.
- Confirmar que a seta fica acessível quando os ícones são ocultados.
- Mover um ícone para cada lado do divisor e confirmar a alternância.
- Confirmar a ocultação após 10 segundos e a persistência das preferências.
- Testar após reiniciar, trocar resolução e conectar outra tela.
- Sair e confirmar que os ícones voltam a aparecer.

Consulte [LICENSE](LICENSE) para a licença do projeto.
