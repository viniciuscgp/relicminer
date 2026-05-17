# Relic Miner - Plano de Implementacao dos Sistemas

Este documento guia a implementacao inicial dos sistemas de stats, inventario,
economia, sobrevivencia e HUD. A prioridade e manter o codigo simples,
plugavel e facil de ler.

## Principios

- Sistemas reutilizaveis ficam em componentes.
- O player, baus, NPCs e inimigos usam o mesmo inventario.
- A UI/HUD fica em cenas separadas, plugadas onde for necessario.
- Dados de itens ficam em Resources, nao espalhados em scripts.
- Scripts de gameplay devem ter nomes claros e pouca responsabilidade.
- Evitar duplicacao: regras comuns ficam em um unico componente.

## Fase 1 - Fundacao plugavel

- [x] Criar este plano de implementacao.
- [x] Criar `ItemDefinition` como Resource de dados de item.
- [x] Criar `ItemStack` para representar item + quantidade + durabilidade.
- [x] Criar `InventoryComponent` reutilizavel para player, bau, inimigo e NPC.
- [x] Criar `PlayerStats` como componente de stats e sobrevivencia.
- [x] Plugar `InventoryComponent` e `PlayerStats` no player atual.
- [x] Criar HUD em cena separada e plugar no player.
- [x] Validar que os scripts carregam no projeto.

## Fase 2 - Interacao e containers

- [x] Criar contrato simples para abrir inventarios de outros objetos.
- [ ] Criar cena base de bau usando `InventoryComponent`.
- [x] Permitir inventarios trancados por `key_id`.
- [ ] Permitir transferir itens entre inventarios.
- [ ] Criar uma UI separada para container/inventario.

## Fase 3 - Itens usaveis

- [ ] Comida recupera fome.
- [ ] Pocoes aplicam efeitos.
- [ ] Tocha tem durabilidade/tempo e apaga na agua.
- [ ] Armas/ferramentas usam dano e durabilidade.

## Fase 4 - Combate e loot

- [ ] Criar componente comum de vida/dano para entidades.
- [ ] Implementar ataque leve do player.
- [ ] Criar inimigo base com inventario de loot.
- [ ] Ao morrer, inimigo fica inspecionavel como container.

## Fase 5 - Economia e NPC

- [ ] Criar dados de loja por NPC.
- [ ] Criar NPCs iniciais: Ferreiro, Herbalista e Comerciante.
- [ ] Comprar/vender usando Coroas.
- [ ] Manter precos de compra e venda separados.

## Fase 6 - Salvamento dificil

- [ ] Criar Pedra de Registro como item.
- [ ] Criar Altar de Registro.
- [ ] Salvar player, inventario, posicao e estado essencial.
- [ ] Morte restaura ultimo registro.
