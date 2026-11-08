// Ponto de entrada das Cloud Functions do RodaJusta.
export { definirPerfil, completarCadastroLojista, completarCadastroEntregador } from "./cadastro.ts";
export {
  enviarPedidos,
  aceitarOferta,
  recusarOferta,
  avancarOnda,
  incluirNoLote,
  responderInclusao,
  expirarInclusao,
  reenviarLote,
} from "./despacho.ts";
export { ficarOnline, pausar, ficarOffline, confirmarColeta, concluirEntrega, naoEntregue, cancelarLote } from "./entrega.ts";
export {
  registrarPagamento,
  responderPagamento,
  resolverContestacao,
  convidarEntregador,
  responderConvite,
  sairDaEquipe,
} from "./financeiro.ts";
export { fecharFaturas, verificarFaturas, marcarFaturaPaga, trocarPlano, definirIsencao, processarBonusSemanal } from "./faturas.ts";
export { coletarMetricas, preverDiaSeguinte, decidirIncentivo, criarIncentivo, criarTurno, reservarTurno } from "./dados.ts";
export { ifoodWebhook, ifoodDespachar, vincularIfood } from "./ifood.ts";
export {
  reivindicarAdmin,
  aprovarCadastro,
  bloquearUsuario,
  salvarParametros,
  salvarZona,
  confirmarVinculoIfood,
  lancarAjuste,
} from "./admin.ts";
