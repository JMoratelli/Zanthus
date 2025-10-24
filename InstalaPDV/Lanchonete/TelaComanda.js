Ext.define("Pdv.view.tela.2.TelaComanda", {
    extend: "Ext.panel.Panel",
    alias: "widget.pdvtelacomanda",
    layout: "border",
    style: "background: #8D9DB3;",
    frame: !0,
    defaults: {
        border: 0
    },
    initComponent: function() {
        this.items = [{
            region: "north",
            xtype: "telatopo",
            flex: 1.2
        }, {
            region: "center",
            xtype: "container",
            layout: {
                type: "hbox",
                align: "stretch"
            },
            border: 0,
            flex: 4,
            items: [{
                xtype: "comanda",
                flex: 1
            }, {
                xtype: "container",
                flex: 1,
                layout: {
                    type: "vbox",
                    align: "stretch"
                },
                items: [{
                    xtype: "container",
                    flex: 2,
                    layout: {
                        type: "vbox",
                        align: "stretch"
                    },
                    items: [{
                        layout: {
                            type: "hbox",
                            align: "stretch"
                        },
                        xtype: "container",
                        flex: 1,
                        defaults: {
                            labelClsExtra: "label-text-display",
                            labelAlign: "left",
                            labelWidth: 90,
                            flex: 0.1,
                            xtype: "visor",
                            margin: "5 15 30 0"
                        },
                        cls: "sub-total",
                        items: [{
                            xtype: "teclafuncional",
                            pdvfn: 3014,
                            text: "Incluir Produto"
                        }, {
                            xtype: "teclafuncional",
                            cls: "bt_teclado_v",
                            pdvfn: 12809,
                            text: "Voltar <br /> Venda"
                        }, {
                            xtype: "teclafuncional",
                            cls: "bt_teclado_y",
                            pdvfn: 11168,
                            text: "Pagar <br />Comanda"
                        }, {
                            xtype: "teclafuncional",
                            cls: "bt_teclado_a",
                            pdvfn: 12807,
                            text: "Liberar Comanda"
                        }]
                    }, {
                        layout: {
                            type: "hbox",
                            align: "stretch"
                        },
                        xtype: "container",
                        flex: 1,
                        defaults: {
                            labelClsExtra: "label-text-display",
                            labelAlign: "left",
                            labelWidth: 90,
                            flex: 0.1,
                            xtype: "visor",
                            margin: "5 15 30 0"
                        },
                        cls: "sub-total",
                        items: [{
                            xtype: "teclagatilho",
                            text: "Imprimir <br /> Comanda",
                            style: "float: left !important",
                            listeners: {
                                click: function() {
                                    Pdv.api.nucleo.Restful.imprimirComanda()
                                }
                            }
                        }, {
                            xtype: "teclagatilho",
                            text: "Confirmar <br /> Itens",
                            style: "float: left !important",
                            cls: "bt_teclado_a",
                            hidden: !__incluirBotaoConfirmarItensComanda,
                            listeners: {
                                click: function() {
                                    Pdv.api.nucleo.Restful.confirmarItensComanda()
                                }
                            }
                        }, {
                            xtype: "teclafuncional",
                            pdvfn: 12804,
                            cls: "bt_teclado_y",
                            text: "Nova <br /> Comanda"
                        }]
                    }]
                }, {
                    xtype: "container",
                    flex: 2,
                    layout: {
                        type: "vbox",
                        align: "stretch"
                    },
                    defaults: {
                        labelClsExtra: "label-text-display",
                        labelAlign: "top",
                        labelWidth: 40,
                        readOnly: !0,
                        xtype: "visor",
                        fieldCls: "input-sub-total"
                    },
                    cls: "sub-total",
                    items: [{
                        value: Pdv.api.sistema.Gerenciador.codComanda,
                        itemId: "dsCodComanda",
                        fieldLabel: "Comanda"
                    }, {
                        value: Pdv.api.sistema.Gerenciador.operadorComanda,
                        itemId: "dsOperadorComanda",
                        fieldLabel: "Operador da Comanda"
                    }, {
                        value: Pdv.api.sistema.Gerenciador.totalComanda,
                        itemId: "dsTotalComanda",
                        fieldLabel: "Total Comanda R$"
                    }]
                }]
            }]
        }];
        this.callParent(arguments)
    }
});
