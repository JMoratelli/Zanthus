Ext.define("Pdv.api.dinamico.pdvMouse.Buttons", {
    singleton: !0,
    arrButtons: [{
        xtype: "teclafuncao",
        itemId: "teclaF1",
        atalho: !0,
        text: "F1 - Fun&ccedil;&atilde;o",
        icon: _resources_icon_11,
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        xtype: "teclafinalizar",
        itemId: "teclaF2",
        text: "F2 - Subtotal",
        evento: 20,
        icon: _resources_icon_5,
        iconAlign: "top",
        atalho: !0,
        cls: "bt_atalho",
        disabled: !0
    }, {
        xtype: "teclafuncional",
        itemId: "teclaF3",
        text: "F3 - Produto",
        pdvfn: 11126,
        icon: _resources_icon_4,
        iconAlign: "top",
        atalho: !0,
        cls: "bt_atalho"
    }, {
        xtype: "teclafuncional",
        itemId: "teclaF4",
        pdvfn: 1771,
        atalho: !0,
        icon: _resources_icon_3,
        text: "F4 - Cliente",
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        xtype: "teclafuncional",
        itemId: "teclaF5",
        atalho: !0,
        pdvfn: 1123,
        text: "F5 - Pesquisa Embalagem",
        icon: _resources_icon_8,
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        autoLabel: "Desconto",
        monetario: 2,
        atalho: !0,
        value: "0,00",
        icon: _resources_icon_12,
        iconAlign: "top",
        text: "F6 - Desconto",
        xtype: "teclagatilho",
        cls: "bt_atalho",
        evento: [8, 7],
        autoColeta: !0,
        semAlteracao: !0,
        multiColeta: !0,
        itemId: "teclaF6",
        itensMultiColeta: {
            tecladoInicialVisivel: !0,
            tbar: [{
                xtype: "label",
                itemId: "visorValorTotal",
                flex: 1,
                margin: "0 10 10 5",
                cls: "label-text-subtotal",
                style: "float:right !important; margin-right: 20px;",
                text: "Valor Bruto: "
            }, {
                xtype: "label",
                itemId: "visorValorDesconto",
                flex: 1,
                margin: "0 10 10 5",
                cls: "label-text-subtotal",
                style: "float:right !important; margin-right: 20px;",
                text: "Valor Liquido: "
            }],
            itens: [{
                xtype: "campoinput",
                itemId: "valorDesconto",
                labelAlign: "top",
                fieldLabel: "Desconto Valor",
                allowBlank: !0,
                msgTarget: "under",
                margin: "0 10 10 5",
                dadoNumerico: !0,
                monetario: 2,
                disposicaoNumerica: "padrao",
                permitirValorDecimal: !0,
                usarDuploZero: !0,
                valorInicial: null,
                width: "98%",
                style: "float:right !important; margin-right: 20px;",
                labelClsExtra: "label-text-subtotal",
                fieldCls: "input-sub-total",
                labelStyle: "opacity: 0.3",
                listeners: {
                    focus: function(a) {
                        a.inputEl.addCls("input-desconto-alterado");
                        a.labelEl.addCls("input-desconto-alterado-label")
                    },
                    blur: function(a) {
                        a.inputEl.removeCls("input-desconto-alterado");
                        a.labelEl.removeCls("input-desconto-alterado-label")
                    }
                }
            }, {
                xtype: "campoinput",
                itemId: "percentualDesconto",
                labelAlign: "top",
                fieldLabel: "Desconto %",
                allowBlank: !0,
                msgTarget: "under",
                margin: "0 10 10 5",
                dadoNumerico: !0,
                monetario: 0,
                disposicaoNumerica: "padrao",
                permitirValorDecimal: !0,
                usarDuploZero: !0,
                valorInicial: null,
                width: "98%",
                style: "float:right !important; margin-right: 20px;",
                labelClsExtra: "label-text-subtotal",
                fieldCls: "input-sub-total",
                labelStyle: "opacity: 0.3",
                listeners: {
                    focus: function(a) {
                        a.inputEl.addCls("input-desconto-alterado");
                        a.labelEl.addCls("input-desconto-alterado-label")
                    },
                    blur: function(a) {
                        a.inputEl.removeCls("input-desconto-alterado");
                        a.labelEl.removeCls("input-desconto-alterado-label")
                    }
                }
            }]
        }
    }, {
        xtype: "teclagatilho",
        itemId: "teclaF8",
        evento: 17,
        monetario: 2,
        atalho: !0,
        autoColeta: !0,
        text: "F8 - Valor",
        value: "0,00",
        icon: _resources_icon_7,
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        xtype: "teclagatilho",
        itemId: "teclaF9",
        autoLabel: "C&oacute;d. Vendedor",
        evento: 3,
        atalho: !0,
        autoColeta: !0,
        text: "F9 - Vendedor",
        icon: _resources_icon_10,
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        xtype: "teclagatilho",
        itemId: "teclaF10",
        evento: 2,
        atalho: !0,
        text: "F10 - Canc. Cupom",
        icon: _resources_icon_1,
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        xtype: "teclafuncional",
        itemId: "teclaF11",
        pdvfn: 11169,
        atalho: !0,
        icon: _resources_icon_2,
        text: "F11 - Pedido",
        iconAlign: "top",
        cls: "bt_atalho"
    }, {
        xtype: "teclafuncional",
        itemId: "teclaF12",
        text: "F12 - Sair",
        pdvfn: 53,
        icon: _resources_icon_6,
        iconAlign: "top",
        cls: "bt_atalho"
    }],
    get: function() {
        return this.arrButtons
    }
});
