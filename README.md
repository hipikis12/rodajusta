<p align="center"><img src="branding/marca-256.png" width="120" alt="RodaJusta"></p>

<h1 align="center">RodaJusta</h1>
<p align="center">Entregas divididas de um jeito justo.</p>

A marca é uma roda com seis partes iguais (o trabalho dividido) e uma parte em âmbar: a vez de alguém no rodízio.

## O que tem aqui

| Pasta | O que é |
| --- | --- |
| `apps/operacao` | App Android das **lojas** e dos **entregadores** (Flutter) |
| `apps/admin` | App **Admin** (Flutter; Android, e roda na web) |
| `packages/core` | Regras compartilhadas em Dart: leitura da comanda, ESC/POS, geohash, valor da entrega |
| `functions` | Cloud Functions (TypeScript): despacho em ondas, aceite, coleta, fatura, incentivos, iFood |
| `firestore.rules`, `storage.rules` | Segurança: o app só lê o que é seu; dinheiro e status só pelo servidor |
| `rules-tests` | Testes das regras no emulador |
| `branding` | Logo e gerador dos ícones |

### Como o sistema funciona

- **Entrada de pedidos:** digitado, colado (texto do WhatsApp etc.), **comanda do PDV** (o celular da loja vira uma impressora) ou **iFood** (entrega própria, por webhook). Tudo cai na mesma tela, com o botão **Enviar** ou **Enviar juntas**.
- **Distribuição justa:** cada pedido (ou lote) vai em **ondas** para quem tem a maior pontuação: proximidade + tempo esperando + entregas por hora no dia + turno de rodízio − recusas recentes. O aceite usa transação: ninguém pega o mesmo pedido duas vezes.
- **Equipe própria:** a loja pode mandar primeiro para os seus entregadores; se ninguém aceitar no tempo configurado, cai no sistema geral.
- **Lote:** várias comandas da mesma loja vão como uma oferta só ("3 entregas"); o entregador aceita todas ou nenhuma. Incluir comanda depois exige o aceite dele.
- **Entrega:** a oferta mostra só o bairro; depois do aceite, PIN de coleta na loja → rota otimizada no Google Maps → "Entregue" só perto do destino (150 m).
- **Dinheiro:** o sistema **não movimenta dinheiro**, só registra os números. Loja marca "paguei", entregador marca "recebi". A taxa da plataforma (por entrega ou mensal) vira uma fatura mensal que o Admin marca como paga.
- **Incentivos:** a cada 15 minutos o sistema mede cada zona (pedidos, entregadores online, tempo de aceite, chuva pela Open-Meteo) e sugere descontos, bônus semanais ou turnos de rodízio para o Admin aprovar.

## Receber comandas do PDV

O celular da loja se passa por impressora térmica e recebe os cupons **com o app aberto ou fechado** (serviço Android em primeiro plano, que liga sozinho quando o celular reinicia). Três jeitos de o PDV "imprimir" nele:

| Jeito | Para quem | Como configurar no PDV |
| --- | --- | --- |
| Bluetooth clássico (SPP) | PDV no Windows com Bluetooth; apps Android que imprimem em impressora pareada | Parear o celular e usar a porta COM criada (driver "Generic / Text Only" ou ESC/POS) |
| Bluetooth BLE | Apps que procuram impressoras portáteis BLE | Procurar impressora no app; o celular anuncia os serviços BLE mais usados por impressoras térmicas |
| Rede (RAW, porta 9100) | PDV em computador na mesma rede | Impressora de rede com "Porta TCP/IP padrão" no IP do celular, porta 9100 |

O que o leitor entende (`packages/core`):

- **ESC/POS e variantes** (Epson, Elgin, Bematech, Daruma, Tanca, clones): todos os comandos de formatação, código de barras, QR, logotipo, gaveta e consultas de status são removidos. O app responde às consultas de status como uma impressora "OK", porque alguns PDVs só imprimem depois disso.
- **Acentos:** CP850, CP860, CP437, Windows-1252 e UTF-8, com detecção automática (muitos PDVs anunciam uma página e mandam outra).
- **Cupom impresso como imagem** (comum em sistemas web e drivers do Windows): a imagem é remontada e lida por OCR no próprio celular (ML Kit), sem internet.
- **Layouts:** rótulos com ou sem acento, com pontilhado, hífen ou colunas; valor na linha de baixo; endereço numa linha só (rua, número, bairro, cidade, UF, CEP); seções sem rótulo; rua e número separados; papel estreito com palavra cortada; zona rural (Linha, Lote, Gleba).
- **Pagamento:** pago online ou cobrar na entrega, em dinheiro, cartão (avisa o entregador para levar maquininha) ou Pix; troco "para" ou "de".
- **Separação:** várias vias num trabalho (corte de papel, `ESC @`, form feed ou comandas coladas). Vias repetidas, via de cozinha, balcão, mesa, reimpressão e o endereço da própria loja no topo do cupom são descartados.
- Comandas guardadas em disco até serem processadas: sem internet, nada se perde.

Quando a loja corrige uma comanda lida errado, o texto original e a correção vão para **Amostras de comandas** no Admin. Coloque esses exemplos em `packages/core/test/comanda_test.dart` e ajuste o leitor.

Em Ajustes → Receber comandas há **Testar leitura / colar pedido**: cole o texto de um cupom para ver o que o app entende (ou criar a comanda direto).

## Testes automáticos

O GitHub Actions roda tudo a cada push (`.github/workflows/ci.yml`):

1. Checagem de tipos e **testes das regras de negócio** (score, ondas, lote, fatura, acerto, rota, gatilhos).
2. **Testes das regras de segurança** do Firestore no emulador.
3. Testes do pacote core (parser de comanda, ESC/POS, geohash).
4. `flutter analyze`, `flutter test` e **compilação dos dois APKs**, que ficam para download na aba *Actions* → execução → *Artifacts*.

Localmente:

```bash
cd functions && npm install && npm test
cd packages/core && dart test
```

## Colocar no ar

1. **Firebase:** crie um projeto em <https://console.firebase.google.com> (plano Blaze, exigido pelas Cloud Functions). Ative **Authentication → Google**, **Firestore** (região `southamerica-east1`), **Storage** e **Cloud Messaging**.
2. **Ligar os apps ao projeto** (em cada app):
   ```bash
   dart pub global activate flutterfire_cli
   cd apps/operacao && flutterfire configure   # repita em apps/admin
   ```
   Isso substitui `lib/firebase_options.dart`. Alternativa: copie `firebase.env.example.json` para `firebase.env.json`, preencha e compile com `--dart-define-from-file=../../firebase.env.json`. No CI, coloque o conteúdo desse JSON no secret `FIREBASE_ENV_JSON` para os APKs já saírem configurados.
3. **Seu acesso de admin:** copie `functions/.env.example` para `functions/.env` e coloque seu e-mail Google em `ADMIN_EMAILS`.
4. **Publicar backend:**
   ```bash
   npm install -g firebase-tools && firebase login
   firebase use --add            # escolha o projeto
   cd functions && npm install && cd ..
   firebase deploy --only firestore,storage,functions
   ```
   As funções do iFood pedem os secrets `IFOOD_CLIENT_ID` e `IFOOD_CLIENT_SECRET` (`firebase functions:secrets:set IFOOD_CLIENT_ID`). Sem credenciais do iFood ainda, publique o resto com `--only functions:` + os nomes, ou cadastre valores provisórios.
5. **Rodar os apps:**
   ```bash
   tool/preparar_android.sh       # gera os arquivos Android padrão (Gradle etc.)
   cd apps/operacao && flutter run
   ```
6. No app Admin, entre com Google e toque em **Sou o administrador**. Cadastre as **zonas** (ex.: centro de Ariquemes com raio de 8 km) em *Parâmetros e zonas*.

Para testar sem projeto real, use os emuladores (`firebase emulators:start`) e rode os apps com `--dart-define=USAR_EMULADOR=true`.

## Pontos para revisar antes de produção

- **iFood:** exige cadastro de integrador e homologação no Portal do Desenvolvedor. Os nomes de campos e a assinatura do webhook estão isolados em `functions/src/ifood.ts` para conferir com a documentação vigente.
- **Recepção de comandas:** teste com o PDV real de cada loja. Os perfis BLE são os mais comuns em impressoras térmicas; um app com perfil diferente precisa ser adicionado em `ReceptorBle.kt`. Em celulares Xiaomi, Samsung e Motorola, libere o app da economia de bateria (o app oferece o atalho).
- **Endereços:** usam o geocodificador do próprio Android (grátis, sem chave). Se a precisão não bastar, troque pela Geocoding API do Google.
- **Extrato em PDF** e **mapa ao vivo** no Admin ainda não foram feitos.
