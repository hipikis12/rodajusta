import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rodajusta_core/rodajusta_core.dart';

import '../../servicos/api.dart';
import '../../servicos/localizacao.dart';
import '../../widgets/comum.dart';
import '../lojista/financeiro_loja.dart' show ExtratoLancamentos;
import 'fatura.dart';
import 'lote_ativo.dart';
import 'oferta.dart';

class HomeEntregador extends StatefulWidget {
  const HomeEntregador({super.key});
  @override
  State<HomeEntregador> createState() => _HomeEntregadorState();
}

class _HomeEntregadorState extends State<HomeEntregador> {
  int _aba = 0;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ofertas;
  String? _ofertaAberta;

  @override
  void initState() {
    super.initState();
    // ofertas chegam pelo Firestore com o app aberto (o push cobre o app fechado)
    _ofertas = db
        .collection('ofertas')
        .where('entregadorId', isEqualTo: uid)
        .where('status', isEqualTo: 'pendente')
        .snapshots()
        .listen(_aoChegarOferta);
  }

  void _aoChegarOferta(QuerySnapshot<Map<String, dynamic>> snap) {
    if (snap.docs.isEmpty || _ofertaAberta != null || !mounted) return;
    final d = snap.docs.first;
    final expira = (d.data()['expiraEm'] as Timestamp?)?.toDate();
    if (expira == null || expira.isBefore(DateTime.now())) return;
    _ofertaAberta = d.id;
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    Navigator.of(context)
        .push(MaterialPageRoute<void>(fullscreenDialog: true, builder: (_) => TelaOferta(id: d.id, oferta: d.data())))
        .whenComplete(() => _ofertaAberta = null);
  }

  @override
  void dispose() {
    _ofertas?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: db.doc('entregadores/$uid').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const Scaffold(body: Carregando());
        final e = snap.data!.data() ?? {};
        final disp = e['disponibilidade'] as String? ?? 'offline';
        // mantém o rastreio ligado só enquanto trabalha
        if (disp == 'disponivel' || disp == 'em_entrega') {
          RastreadorEntregador.instancia.iniciar(emEntrega: disp == 'em_entrega');
        } else {
          RastreadorEntregador.instancia.parar();
        }
        final telas = [
          e['loteAtivoId'] != null ? LoteAtivo(loteId: e['loteAtivoId'] as String) : _Inicio(e: e),
          const _Ganhos(),
          const TelaFatura(),
          _Perfil(e: e),
        ];
        return Scaffold(
          body: SafeArea(child: IndexedStack(index: _aba, children: telas)),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _aba,
            onDestinationSelected: (i) => setState(() => _aba = i),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.two_wheeler), label: 'Início'),
              NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Ganhos'),
              NavigationDestination(icon: Icon(Icons.receipt_long_outlined), label: 'Fatura'),
              NavigationDestination(icon: Icon(Icons.person_outline), label: 'Perfil'),
            ],
          ),
        );
      },
    );
  }
}

class _Inicio extends StatelessWidget {
  const _Inicio({required this.e});
  final Map<String, dynamic> e;

  Future<void> _ficarOnline(BuildContext context) async {
    String trabalhaEm = 'geral';
    if (e['lojaEquipeId'] != null) {
      final escolha = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Onde você vai trabalhar hoje?')),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: Text('Só ${e['lojaEquipeNome'] ?? 'minha loja'}'),
              onTap: () => Navigator.pop(c, 'loja'),
            ),
            ListTile(
              leading: const Icon(Icons.public),
              title: Text('${e['lojaEquipeNome'] ?? 'Minha loja'} e sistema geral'),
              onTap: () => Navigator.pop(c, 'ambos'),
            ),
            ListTile(leading: const Icon(Icons.map), title: const Text('Só sistema geral (folga da loja)'), onTap: () => Navigator.pop(c, 'geral')),
          ]),
        ),
      );
      if (escolha == null) return;
      trabalhaEm = escolha;
    }
    if (!context.mounted) return;
    await executar(context, () async {
      final p = await posicaoAtual(precisaSempre: true);
      try {
        return await chamar('ficarOnline', {
          'lat': p.latitude,
          'lng': p.longitude,
          'precisao': p.accuracy,
          'mock': p.isMocked,
          'trabalhaEm': trabalhaEm,
        });
      } on ErroApi catch (erro) {
        final texto = rotulosMotivoBloqueio[erro.motivo];
        throw texto == null ? erro : ErroApi(texto);
      }
    });
  }

  Future<void> _ficarOffline(BuildContext context) async {
    final r = await executar(context, () => chamar('ficarOffline'));
    if (r == null || !context.mounted) return;
    final porLoja = (r['porLoja'] as List? ?? []).map((x) => Map<String, dynamic>.from(x as Map)).toList();
    await showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Resumo do dia'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          LinhaValor('Entregas', '${r['entregas']}'),
          LinhaValor('Tempo online', '${(r['minutosOnline'] as num? ?? 0) ~/ 60}h ${(r['minutosOnline'] as num? ?? 0).toInt() % 60}min'),
          const Divider(),
          for (final l in porLoja) LinhaValor('${l['lojaNome']} (${l['entregas']})', formatarReais((l['centavos'] as num).toInt())),
        ]),
        actions: [FilledButton(onPressed: () => Navigator.pop(c), child: const Text('OK'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disp = e['disponibilidade'] as String? ?? 'offline';
    final online = disp == 'disponivel';
    final stats = e['statsHoje'] as Map? ?? {};
    final cor = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Row(children: [
        const Marca(tamanho: 40),
        const SizedBox(width: 12),
        Expanded(child: Text('Olá, ${(e['nome'] as String? ?? '').split(' ').first}', style: Theme.of(context).textTheme.titleLarge)),
      ]),
      const SizedBox(height: 16),
      Card(
        margin: EdgeInsets.zero,
        color: online ? cor.primaryContainer : cor.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(children: [
            Icon(online ? Icons.radar : (disp == 'pausado' ? Icons.pause_circle : Icons.bedtime), size: 48),
            const SizedBox(height: 8),
            Text(
              online ? 'Você está na fila' : (disp == 'pausado' ? 'Pausado' : 'Você está offline'),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(online
                ? 'As ofertas aparecem aqui em tela cheia. Quem espera mais sobe na fila.'
                : 'Fique online para receber entregas perto de você.'),
            const SizedBox(height: 16),
            if (!online)
              FilledButton.icon(
                onPressed: () => _ficarOnline(context),
                icon: const Icon(Icons.play_arrow),
                label: Text(disp == 'pausado' ? 'Voltar para a fila' : 'Ficar online'),
              ),
            if (online)
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => executar(context, () => chamar('pausar')),
                    icon: const Icon(Icons.pause),
                    label: const Text('Pausar'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _ficarOffline(context),
                    icon: const Icon(Icons.stop),
                    label: const Text('Encerrar dia'),
                  ),
                ),
              ]),
            if (disp == 'pausado')
              TextButton(onPressed: () => _ficarOffline(context), child: const Text('Encerrar o dia')),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _Numero('Entregas hoje', '${stats['entregas'] ?? 0}')),
        const SizedBox(width: 12),
        Expanded(child: _Numero('Online hoje', '${((stats['minutosOnline'] as num? ?? 0) / 60).toStringAsFixed(1)} h')),
      ]),
      const SizedBox(height: 16),
      _Incentivos(zonaId: e['zonaId'] as String? ?? 'padrao'),
    ]);
  }
}

class _Numero extends StatelessWidget {
  const _Numero(this.rotulo, this.valor);
  final String rotulo;
  final String valor;
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(rotulo),
            Text(valor, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
          ]),
        ),
      );
}

/// Incentivos ativos ou agendados para a zona do entregador.
class _Incentivos extends StatelessWidget {
  const _Incentivos({required this.zonaId});
  final String zonaId;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('incentivos').where('zonaId', whereIn: [zonaId, 'todas']).where('status', isEqualTo: 'ativo').snapshots(),
      builder: (context, snap) {
        final agora = DateTime.now();
        final lista = (snap.data?.docs ?? [])
            .where((d) => (d.data()['fim'] as Timestamp?)?.toDate().isAfter(agora) ?? false)
            .toList();
        if (lista.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Incentivos', style: Theme.of(context).textTheme.titleMedium),
          for (final d in lista)
            Card(
              margin: const EdgeInsets.only(top: 8),
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                leading: Icon(d.data()['tipo'] == 'chuva' ? Icons.umbrella : Icons.local_fire_department),
                title: Text(d.data()['modo'] == 'bonus'
                    ? 'Bônus de ${d.data()['percentual']}% (mín. ${d.data()['minimoEntregas']} entregas)'
                    : '${d.data()['percentual']}% de desconto na taxa'),
                subtitle: Text('${d.data()['motivo'] ?? ''}\nAté ${dataHora(d.data()['fim'])}'),
                isThreeLine: true,
              ),
            ),
        ]);
      },
    );
  }
}

class _Ganhos extends StatelessWidget {
  const _Ganhos();
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(title: const Text('Ganhos'), bottom: const TabBar(tabs: [Tab(text: 'Por loja'), Tab(text: 'Extrato')])),
        body: TabBarView(children: [
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: db.collection('acertos').where('entregadorId', isEqualTo: uid).orderBy('atualizadoEm', descending: true).snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) return const Carregando();
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Vazio('Seus ganhos por loja aparecem aqui depois das entregas.');
              final aReceber = docs.fold<int>(0, (s, d) => s + (d.data()['saldoCentavos'] as num? ?? 0).toInt());
              return ListView(children: [
                Padding(padding: const EdgeInsets.all(16), child: LinhaValor('Total a receber', formatarReais(aReceber), destaque: true)),
                for (final d in docs)
                  Card(
                    child: ListTile(
                      title: Text(d.data()['lojaNome'] as String? ?? ''),
                      subtitle: Text(
                        '${d.data()['qtdEntregas'] ?? 0} entregas · ganho ${formatarReais((d.data()['entregasCentavos'] as num? ?? 0).toInt())}'
                        '\nRecebido ${formatarReais((d.data()['pagosCentavos'] as num? ?? 0).toInt())}'
                        '${(d.data()['pendentesCentavos'] as num? ?? 0) > 0 ? ' · confirme ${formatarReais((d.data()['pendentesCentavos'] as num).toInt())} no Extrato' : ''}',
                      ),
                      isThreeLine: true,
                      trailing: Text(formatarReais((d.data()['saldoCentavos'] as num? ?? 0).toInt()),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
              ]);
            },
          ),
          const ExtratoLancamentos(campo: 'entregadorId'),
        ]),
      ),
    );
  }
}

class _Perfil extends StatelessWidget {
  const _Perfil({required this.e});
  final Map<String, dynamic> e;
  @override
  Widget build(BuildContext context) {
    return ListView(children: [
      ListTile(
        leading: const CircleAvatar(child: Icon(Icons.person)),
        title: Text(e['nome'] as String? ?? ''),
        subtitle: Text('${e['veiculo'] ?? ''} ${e['placa'] ?? ''}'),
      ),
      Card(
        child: ListTile(
          title: const Text('Seu código de convite'),
          subtitle: const Text('Passe para a loja que quer você na equipe própria.'),
          trailing: SelectableText(e['codigoConvite'] as String? ?? '',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2)),
        ),
      ),
      if (e['lojaEquipeId'] != null)
        Card(
          child: ListTile(
            leading: const Icon(Icons.storefront),
            title: Text('Equipe: ${e['lojaEquipeNome'] ?? ''}'),
            trailing: TextButton(
              onPressed: () => executar(context, () => chamar('sairDaEquipe')),
              child: const Text('Sair da equipe'),
            ),
          ),
        ),
      StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: db.collection('convites').where('entregadorId', isEqualTo: uid).where('status', isEqualTo: 'pendente').snapshots(),
        builder: (context, snap) => Column(children: [
          for (final c in snap.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])
            Card(
              color: Theme.of(context).colorScheme.secondaryContainer,
              child: ListTile(
                title: Text('${c.data()['lojaNome']} convidou você para a equipe'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => executar(context, () => chamar('responderConvite', {'lojistaId': c.data()['lojistaId'], 'aceitar': false})),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.check),
                    onPressed: () => executar(context, () => chamar('responderConvite', {'lojistaId': c.data()['lojistaId'], 'aceitar': true})),
                  ),
                ]),
              ),
            ),
        ]),
      ),
      _Turnos(zonaId: e['zonaId'] as String? ?? 'padrao'),
      const Divider(),
      ListTile(leading: const Icon(Icons.logout), title: const Text('Sair'), onTap: () => FirebaseAuth.instance.signOut()),
    ]);
  }
}

/// Turnos de rodízio abertos pelo Admin: quem reserva e cumpre ganha prioridade.
class _Turnos extends StatelessWidget {
  const _Turnos({required this.zonaId});
  final String zonaId;
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: db.collection('turnos').where('zonaId', isEqualTo: zonaId).where('fim', isGreaterThan: Timestamp.now()).snapshots(),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.fromLTRB(16, 16, 16, 0), child: Text('Turnos de rodízio')),
          for (final t in docs)
            Builder(builder: (context) {
              final reservados = (t.data()['reservados'] as List? ?? []).cast<String>();
              final meu = reservados.contains(uid);
              final vagas = (t.data()['vagas'] as num).toInt() - reservados.length;
              return ListTile(
                title: Text('${dataHora(t.data()['inicio'])} até ${dataHora(t.data()['fim'])}'),
                subtitle: Text(meu ? 'Reservado: você tem prioridade nesse horário' : '$vagas vagas'),
                trailing: TextButton(
                  onPressed: (!meu && vagas <= 0)
                      ? null
                      : () => executar(context, () => chamar('reservarTurno', {'turnoId': t.id, 'cancelar': meu})),
                  child: Text(meu ? 'Cancelar' : 'Reservar'),
                ),
              );
            }),
        ]);
      },
    );
  }
}
