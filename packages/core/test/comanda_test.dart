import 'package:rodajusta_core/rodajusta_core.dart';
import 'package:test/test.dart';

// Layouts de exemplo com estilos diferentes de PDV (rótulos com pontilhado,
// seções sem rótulo, endereço "formatado" numa linha, valor na linha de
// baixo, papel de 32 colunas...). Não são cópias de nenhum sistema
// específico: quando aparecer um formato real que falhe, ele entra aqui.

void main() {
  test('rótulos com pontilhado, tudo maiúsculo e loja no topo', () {
    final c = extrairComanda('''
        LANCHONETE BOM SABOR
     CNPJ 12.345.678/0001-90
   AV. CANAA, 1500 - CENTRO
      FONE (69) 3535-1234
----------------------------------------
PEDIDO N. 0123            07/11/2026 20:15
CLIENTE.....: JOAO DA SILVA
TELEFONE....: (69) 98111-2233
ENDERECO....: RUA DOS PIONEIROS, 345
BAIRRO......: JARDIM PRIMAVERA
COMPLEMENTO.: CASA AMARELA
REFERENCIA..: PROXIMO AO MERCADO
----------------------------------------
QTD  DESCRICAO                    VALOR
2    X-BURGUER                    36,00
1    REFRIGERANTE LATA             6,00
----------------------------------------
SUBTOTAL                          42,00
TAXA DE ENTREGA                    5,00
TOTAL                             47,00
PAGAMENTO: CARTAO DE CREDITO (LEVAR MAQUINA)
''');
    expect(c.numero, '0123');
    expect(c.cliente, 'JOAO DA SILVA');
    expect(c.telefone, '69981112233');
    expect(c.endereco, 'RUA DOS PIONEIROS, 345');
    expect(c.bairro, 'JARDIM PRIMAVERA');
    expect(c.complemento, 'CASA AMARELA');
    expect(c.referencia, 'PROXIMO AO MERCADO');
    expect(c.itens, ['2x X-burguer', '1x Refrigerante Lata']);
    expect(c.taxaEntregaCentavos, 500);
    expect(c.totalCentavos, 4700);
    expect(c.cobrar, isTrue);
    expect(c.valorCobrarCentavos, 4700);
    expect(c.formaCobranca, 'cartao');
    expect(c.tipo, TipoComanda.entrega);
    expect(c.enderecoDoTopo, isFalse);
    expect(c.confianca, greaterThanOrEqualTo(0.9));
  });

  test('endereço completo numa linha (rua, número, bairro, cidade, UF, CEP) e pago online', () {
    final c = extrairComanda('''
Pedido #4821
Entrega
Cliente: Maria Souza
Telefone: 0800 705 0505 ID: 12345678
Endereço: Rua Tiradentes, 1520 - Setor 03, Ariquemes - RO, 76870-000
Complemento: Apto 12
Referência: Ao lado da farmácia
Itens
1x Pizza Grande Calabresa   R\$ 59,90
   - Borda recheada
1x Guaraná 2L               R\$ 12,00
Subtotal                    R\$ 71,90
Taxa de entrega             R\$ 6,00
Total                       R\$ 77,90
Pagamento: Crédito - PAGO ONLINE
NÃO COBRAR DO CLIENTE
''');
    expect(c.numero, '4821');
    expect(c.cliente, 'Maria Souza');
    expect(c.localizador, '1234 5678');
    expect(c.endereco, 'Rua Tiradentes, 1520');
    expect(c.bairro, 'Setor 03');
    expect(c.cidade, 'Ariquemes');
    expect(c.uf, 'RO');
    expect(c.cep, '76870-000');
    expect(c.complemento, 'Apto 12');
    expect(c.referencia, 'Ao lado da farmácia');
    expect(c.itens, ['1x Pizza Grande Calabresa', '1x Guaraná 2L']);
    expect(c.totalCentavos, 7790);
    expect(c.taxaEntregaCentavos, 600);
    expect(c.cobrar, isFalse);
    expect(c.enderecoParaMapa, 'Rua Tiradentes, 1520, Setor 03, Ariquemes - RO, 76870-000');
  });

  test('seções sem rótulo, cidade/UF e CEP soltos, troco para', () {
    final c = extrairComanda('''
*** DELIVERY ***
Senha: 57
DADOS DO CLIENTE
Ana Paula
(69) 99988-7766
ENDEREÇO DE ENTREGA
Av. Capitão Silvio, 3011
Bairro Jardim Jorge Teixeira
Ariquemes/RO
CEP 76873-512
Próximo ao posto
PRODUTOS
1 Marmitex Grande          R\$ 22,00
1 Suco Natural             R\$ 8,00
TOTAL: R\$ 35,00
Forma de pagamento: Dinheiro
Troco para R\$ 50,00
''');
    expect(c.numero, '57');
    expect(c.cliente, 'Ana Paula');
    expect(c.telefone, '69999887766');
    expect(c.endereco, 'Av. Capitão Silvio, 3011');
    expect(c.bairro, 'Jardim Jorge Teixeira');
    expect(c.cidade, 'Ariquemes');
    expect(c.uf, 'RO');
    expect(c.cep, '76873-512');
    expect(c.referencia, 'Próximo ao posto');
    expect(c.itens, ['1x Marmitex Grande', '1x Suco Natural']);
    expect(c.totalCentavos, 3500);
    expect(c.cobrar, isTrue);
    expect(c.formaCobranca, 'dinheiro');
    expect(c.trocoParaCentavos, 5000);
  });

  test('zona rural, rótulos com hífen e "Troco: X" (valor do troco)', () {
    final c = extrairComanda('''
COMANDA 88
Cliente - Seu Zé
Fone 69 99911-2222
End: Linha C-75, Lote 12, Gleba Bom Jesus, depois da ponte
Obs: entregar na porteira
2 x Marmita P   30,00
Total........: 30,00
Dinheiro. Troco: R\$ 20,00
''');
    expect(c.numero, '88');
    expect(c.cliente, 'Seu Zé');
    expect(c.telefone, '69999112222');
    expect(c.endereco, startsWith('Linha C-75, Lote 12'));
    expect(c.observacao, 'entregar na porteira');
    expect(c.itens, ['2x Marmita P']);
    expect(c.totalCentavos, 3000);
    expect(c.cobrar, isTrue);
    expect(c.trocoParaCentavos, 5000); // 30 + 20 de troco
  });

  test('valor na linha de baixo do rótulo', () {
    final c = extrairComanda('''
Pedido 31
Cliente:
Marcos Lima
Endereço:
Rua das Flores, 100
Bairro:
Centro
Total
R\$ 25,00
''');
    expect(c.cliente, 'Marcos Lima');
    expect(c.endereco, 'Rua das Flores, 100');
    expect(c.bairro, 'Centro');
    expect(c.totalCentavos, 2500);
  });

  test('endereço cortado no meio da palavra em papel estreito', () {
    final c = extrairComanda('''
Pedido: 15
Endereco: Rua Presidente Juscel
ino Kubitschek, 2200 - Setor 02
Total: 15,00
''');
    expect(c.endereco, 'Rua Presidente Juscelino Kubitschek, 2200');
    expect(c.bairro, 'Setor 02');
  });

  test('rua e número em rótulos separados', () {
    final c = extrairComanda('''
Pedido 5
Rua: Jamari
Número: 1200
Bairro: Setor 01
''');
    expect(c.endereco, 'Rua Jamari, 1200');
    expect(c.bairro, 'Setor 01');
  });

  test('endereço da loja no topo não vira endereço de entrega', () {
    final c = extrairComanda('''
PIZZARIA SOL
Rua Jamari, 2000 - Centro
(69) 3535-0000
PEDIDO 9
Cliente: Bia
Endereço: Rua Castanheira, 45 - Setor 05
TOTAL 40,00
''');
    expect(c.endereco, 'Rua Castanheira, 45');
    expect(c.bairro, 'Setor 05');
    expect(c.telefone, '');
    expect(c.enderecoDoTopo, isFalse);
  });

  test('só o endereço do topo: usa, mas sem confiar', () {
    final c = extrairComanda('''
PIZZARIA SOL
Rua Jamari, 2000 - Centro
PEDIDO 9
1x Pizza 40,00
TOTAL 40,00
''');
    expect(c.endereco, 'Rua Jamari, 2000');
    expect(c.enderecoDoTopo, isTrue);
    expect(c.confianca, lessThanOrEqualTo(0.5));
  });

  test('pagamentos', () {
    String base(String pg) => 'Pedido 1\nEndereço: Rua A, 1 - Centro\nTotal: 50,00\n$pg';
    expect(extrairComanda(base('Pagamento: PIX (pago)')).cobrar, isFalse);
    expect(extrairComanda(base('Pagamento: Pix')).cobrar, isFalse);
    final cartao = extrairComanda(base('Pagamento: Cartão na entrega'));
    expect(cartao.cobrar, isTrue);
    expect(cartao.formaCobranca, 'cartao');
    expect(extrairComanda(base('Pagamento: Dinheiro\nValor a cobrar: R\$ 0,00')).cobrar, isFalse);
    final parcial = extrairComanda(base('Pago: 20,00\nFalta pagar: 30,00'));
    expect(parcial.cobrar, isTrue);
    expect(parcial.valorCobrarCentavos, 3000);
    expect(extrairComanda(base('Pagamento: Dinheiro - sem troco')).trocoParaCentavos, isNull);
  });

  test('agendamento entra na descrição', () {
    final c = extrairComanda('Pedido 2\nAgendado para 20:30\nEndereço: Rua B, 2 - Centro');
    expect(c.agendadoPara, '20:30');
    expect(c.descricao, contains('agendado 20:30'));
  });

  test('retirada no balcão e mesa não são entrega', () {
    expect(extrairComanda('PEDIDO 300\nRETIRADA NO BALCÃO\nCliente: Carlos\n1x Açaí 18,00\nTOTAL 18,00').tipo,
        TipoComanda.retirada);
    expect(extrairComanda('Mesa 4\n2x Chopp 20,00\nTotal 20,00').tipo, TipoComanda.mesa);
  });

  group('trabalho inteiro', () {
    const entrega = 'PEDIDO 77\nCliente: Rita\nEndereço: Rua Rio Branco, 80 - Centro\nTotal 20,00';

    test('via de cozinha do mesmo pedido é descartada', () {
      final r = lerTrabalho(['VIA COZINHA\nPEDIDO 77\n2x Pastel de carne', entrega]);
      expect(r.entregas.single.cliente, 'Rita');
      expect(r.ignoradas.single, contains('cozinha'));
    });

    test('duas vias iguais viram uma entrega', () {
      final r = lerTrabalho([entrega, entrega]);
      expect(r.entregas, hasLength(1));
      expect(r.ignoradas.single, contains('repetida'));
    });

    test('duas comandas coladas sem corte são separadas', () {
      final r = lerTrabalho([
        'PEDIDO 1001\nCliente: A\nEndereço: Rua Um, 1 - Centro\nTOTAL 10,00\n'
            'PEDIDO 1002\nCliente: B\nEndereço: Rua Dois, 2 - Centro\nTOTAL 20,00',
      ]);
      expect(r.entregas.map((e) => e.numero), ['1001', '1002']);
    });

    test('teste de impressão e cupom de balcão são ignorados', () {
      final r = lerTrabalho(['Teste de impressão - Página de teste do Windows', 'PEDIDO 5\nBALCÃO\n1x Café 5,00\nTotal 5,00']);
      expect(r.entregas, isEmpty);
      expect(r.ignoradas, hasLength(2));
    });
  });
}
