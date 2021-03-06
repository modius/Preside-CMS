/**
 * @singleton true
 */
component {

// CONSTRUCTOR
	/**
	 * @formDirectories.inject           presidecms:directories:forms
	 * @presideObjectService.inject      PresideObjectService
	 * @siteService.inject               SiteService
	 * @validationEngine.inject          ValidationEngine
	 * @i18n.inject                      coldbox:plugin:i18n
	 * @coldbox.inject                   coldbox
	 * @presideFieldRuleGenerator.inject PresideFieldRuleGenerator
	 * @featureService.inject            featureService
	 * @defaultContextName.inject        coldbox:fwSetting:EventAction
	 * @configuredControls.inject        coldbox:setting:formControls
	 */
	public any function init(
		  required array  formDirectories
		, required any    presideObjectService
		, required any    siteService
		, required any    validationEngine
		, required any    i18n
		, required any    coldbox
		, required any    presideFieldRuleGenerator
		, required any    featureService
		, required string defaultContextName
		, required struct configuredControls
	) {
		_setValidationEngine( arguments.validationEngine );
		_setPresideObjectService( arguments.presideObjectService );
		_setI18n( arguments.i18n );
		_setColdbox( arguments.coldbox );
		_setFormDirectories( arguments.formDirectories );
		_setPresideFieldRuleGenerator( arguments.presideFieldRuleGenerator );
		_setFeatureService( arguments.featureService );
		_setDefaultContextName( arguments.defaultContextName );
		_setConfiguredControls( arguments.configuredControls );
		_setSiteService( arguments.siteService );

		_loadForms();

		return this;
	}

// PUBLIC API METHODS
	public array function listForms() {
		var forms = StructKeyArray( _getForms() );

		ArraySort( forms, "textnocase" );

		return forms;
	}

	public boolean function formExists( required string formName, boolean checkSiteTemplates=true ) {
		var forms = _getForms();

		return StructKeyExists( forms, arguments.formName ) || ( arguments.checkSiteTemplates && StructKeyExists( forms, _getSiteTemplatePrefix() & arguments.formName ) );
	}

	public struct function getForm( required string formName, boolean autoMergeSiteForm=true ) {
		var forms        = _getForms();
		var objectName   = "";
		var form         = "";

		if ( arguments.autoMergeSiteForm ) {
			var siteTemplateFormName   = _getSiteTemplatePrefix() & arguments.formName;
			var siteTemplateFormExists = siteTemplateFormName != arguments.formName && formExists( siteTemplateFormName, false );

			if ( siteTemplateFormExists ) {
				if ( formExists( arguments.formName, false )  ) {
					return mergeForms( arguments.formName, siteTemplateFormName, false );
				}

				return forms[ siteTemplateFormName ];
			}
		}

		if ( formExists( arguments.formName ) ) {
			return forms[ arguments.formName ];
		}

		objectName = _getPresideObjectNameFromFormNameByConvention( arguments.formName );
		if ( _getPresideObjectService().objectExists( objectName ) ) {
			return getDefaultFormForPresideObject( objectName );
		}

		throw(
			  type = "FormsService.MissingForm"
			, message = "The form, [#arguments.formName#], could not be found"
		);
	}

	public struct function mergeForms( required string formName, required string mergeWithFormName, boolean autoMergeSiteForm=true ) {
		var mergedName = getMergedFormName( arguments.formName, arguments.mergeWithFormName, false );

		if ( formExists( mergedName ) ) {
			return getForm( mergedName );
		}

		var merged = _mergeForms(
			  form1 = Duplicate( getForm( arguments.formName, arguments.autoMergeSiteForm ) )
			, form2 = Duplicate( getForm( arguments.mergeWithFormName, arguments.autoMergeSiteForm ) )
		);

		_registerForm( mergedName, merged );

		return merged;
	}

	public struct function getFormField( required string formName, required string fieldName ) {
		var frm = getForm( arguments.formName );

		for( var tab in frm.tabs ){
			for( var fieldset in tab.fieldsets ) {
				for( var field in fieldset.fields ) {
					if ( ( field.name ?: "" ) eq arguments.fieldName ) {
						return field;
					}
				}
			}
		}

		throw(
			  type = "FormsService.MissingField"
			, message = "The form field, [#arguments.fieldName#], could not be found in the form, [#arguments.formName#]"
		);
	}

	public any function listFields( required string formName ) {
		var frm    = getForm( arguments.formName );
		var fields = [];

		for( var tab in frm.tabs ){
			if ( IsBoolean( tab.deleted ?: "" ) && tab.deleted ) {
				continue;
			}
			for( var fieldset in tab.fieldsets ) {
				if ( IsBoolean( fieldset.deleted ?: "" ) && fieldset.deleted ) {
					continue;
				}
				for( var field in fieldset.fields ) {
					if ( ( field.control ?: "" ) != "readonly" && !( IsBoolean( field.deleted ?: "" ) && field.deleted ) ) {
						ArrayAppend( fields, field.name ?: "" );
					}
				}
			}
		}

		return fields;
	}

	public struct function getDefaultFormForPresideObject( required string objectName ) {
		var fields = _getPresideObjectService().getObjectProperties( objectName = arguments.objectName );
		var formLayout = {
			tabs = [{
				title       = "",
				description = "",
				id          = "default",
				fieldsets   = [{
					title       = "",
					description = "",
					fields      = [],
					id          = "default"
				}]
			}]
		};

		for( var fieldName in fields ){
			var field = fields[ fieldName ];
			if ( field.getAttribute( "control", "" ) neq "none" ) {
				ArrayAppend( formLayout.tabs[1].fieldsets[1].fields, field.getMemento() );

				formLayout.tabs[1].fieldsets[1].fields[ ArrayLen( formLayout.tabs[1].fieldsets[1].fields ) ].sourceObject = arguments.objectName;
			}
		}

		_applyDefaultLabellingToForm( formName="preside-objects.#objectName#.default", frm=formLayout );

		return formLayout;
	}

	public string function renderForm(
		  required string  formName
		,          string  mergeWithFormName    = ""
		,          string  context              = "admin"
		,          string  fieldLayout          = "formcontrols.layouts.field"
		,          string  fieldsetLayout       = "formcontrols.layouts.fieldset"
		,          string  tabLayout            = "formcontrols.layouts.tab"
		,          string  formLayout           = "formcontrols.layouts.form"
		,          string  formId               = ""
		,          string  component            = ""
		,          any     validationResult     = ""
		,          boolean includeValidationJs  = true
		,          struct  savedData            = {}
		,          string  fieldNamePrefix      = ""
		,          string  fieldNameSuffix      = ""
		,          array   suppressFields       = []
	) {
		var frm               = Len( Trim( arguments.mergeWithFormName ) ) ? mergeForms( arguments.formName, arguments.mergeWithFormName) : getForm( arguments.formName );
		var coldbox           = _getColdbox();
		var i18n              = _getI18n();
		var renderedTabs      = CreateObject( "java", "java.lang.StringBuffer" );
		var activeTab         = true;
		var renderedFieldSets = "";
		var renderedFields    = "";
		var renderArgs        = "";
		var tabs              = [];

		for( var tab in frm.tabs ){
			if ( IsBoolean( tab.deleted ?: "" ) && tab.deleted ) {
				continue;
			}

			renderedFieldSets = CreateObject( "java", "java.lang.StringBuffer" );
			if ( not Len( Trim( tab.id ?: "" ) ) ) {
				tab.id = CreateUUId();
			}

			for( var fieldset in tab.fieldsets ) {
				if ( IsBoolean( fieldset.deleted ?: "" ) && fieldset.deleted ) {
					continue;
				}

				renderedFields = CreateObject( "java", "java.lang.StringBuffer" );

				for( var field in fieldset.fields ) {
					if ( ( IsBoolean( field.deleted ?: "" ) && field.deleted ) || arguments.suppressFields.findNoCase( field.name ) ) {
						continue;
					}
					if ( ( field.control ?: "default" ) neq "none" ) {
						renderArgs = {
							  name               = arguments.fieldNamePrefix & ( field.name ?: "" ) & arguments.fieldNameSuffix
							, type               = field.control ?: "default"
							, context            = arguments.context
							, savedData          = arguments.savedData
						};

						if ( not IsSimpleValue( validationResult ) and validationResult.fieldHasError( field.name ) ) {
							renderArgs.error = i18n.translateResource(
								  uri          = validationResult.getError( field.name )
								, defaultValue = validationResult.getError( field.name )
								, data         = validationResult.listErrorParameterValues( field.name )
							);
						}

						if ( renderArgs.type eq "default" ) {
							renderArgs.type = _getDefaultFormControl( argumentCollection = field );
						}

						if ( StructKeyExists( arguments.savedData, field.name ) ) {
							renderArgs.defaultValue = arguments.savedData[ field.name ];
						} else if ( StructKeyExists( field, "default" ) ) {
							renderArgs.defaultValue = field.default;
						}

						renderArgs.layout = field.layout ?: _formControlHasLayout( renderArgs.type ) ? arguments.fieldlayout : "";

						StructAppend( renderArgs, field, false );
						StructAppend( renderArgs, _getI18nFieldAttributes( field=field ) );

						renderedFields.append( renderFormControl( argumentCollection=renderArgs ) );
					}
				}

				renderArgs = Duplicate( fieldset );
				renderArgs.content = renderedFields.toString();
				renderArgs.append( _getI18nTabOrFieldsetAttributes( fieldset ) );

				renderedFieldSets.append( coldbox.renderViewlet(
					  event = ( fieldset.layout ?: arguments.fieldsetLayout )
					, args  = renderArgs
				) );
			}

			renderArgs         = Duplicate( tab );
			renderArgs.content = renderedFieldSets.toString();
			renderArgs.active  = activeTab;
			renderArgs.append( _getI18nTabOrFieldsetAttributes( tab ) );

			tabs.append( renderArgs );

			renderedTabs.append( coldbox.renderViewlet(
				  event = ( tab.layout ?: arguments.tabLayout )
				, args  = renderArgs
			) );
			activeTab = false;
		}

		return coldbox.renderViewlet( event=arguments.formLayout, args={
			  formId             = arguments.formId
			, content            = renderedTabs.toString()
			, tabs               = tabs
			, validationResult   = arguments.validationResult
			, validationJs       = arguments.includeValidationJs ? getValidationJs( arguments.formName, arguments.mergeWithFormName ) : ""
		} );
	}

	public string function renderFormControl(
		  required string  name
		, required string  type
		,          string  context      = _getDefaultContextName()
		,          string  id           = arguments.name
		,          string  label        = ""
		,          string  savedValue   = ""
		,          string  defaultValue = ""
		,          string  help         = ""
		,          struct  savedData    = {}
		,          string  error        = ""
		,          boolean required     = false
		,          string  layout       = "formcontrols.layouts.field"

	) {
		var coldbox         = _getColdbox();
		var handler         = _getFormControlHandler( type=arguments.type, context=arguments.context );
		var renderedControl = "";

		try {
			renderedControl = coldbox.renderViewlet(
				  event = handler
				, args  = arguments
			);
		} catch ( "HandlerService.EventHandlerNotRegisteredException" e ) {
			renderedControl = "**control, [#arguments.type#], not found**";
		} catch ( "missinginclude" e ) {
			renderedControl = "**control, [#arguments.type#], not found**";
		}

		if ( Len( Trim( arguments.layout ) ) && Len( Trim( renderedControl ) ) ) {
			var layoutArgs = {
				  control  = renderedControl
				, label    = arguments.label
				, for      = arguments.id
				, error    = arguments.error
				, required = arguments.required
				, help     = arguments.help
			};
			layoutArgs.append( arguments, false );

			renderedControl = coldbox.renderViewlet(
				  event = arguments.layout
				, args  = layoutArgs
			);
		}

		return renderedControl;
	}

	public any function validateForm( required string formName, required struct formData, boolean preProcessData=true, boolean ignoreMissing=false ) {
		var ruleset = _getValidationRulesetFromFormName( arguments.formName );
		var data    = Duplicate( arguments.formData );

		// add active "site" id to form data, should unique indexes require checking against a specific site
		data.site = data.site ?: _getColdBox().getRequestContext().getSiteId();

		if ( arguments.preProcessData ) {
			return _getValidationEngine().validate(
				  ruleset       = ruleset
				, data          = data
				, result        = preProcessForm( argumentCollection = arguments )
				, ignoreMissing = arguments.ignoreMissing
			);
		}

		return _getValidationEngine().validate(
			  ruleset = ruleset
			, data    = data
		);
	}

	public any function getValidationJs( required string formName, string mergeWithFormName="" ) {
		var validationFormName = Len( Trim( mergeWithFormName ) ) ? getMergedFormName( formName, mergeWithFormName ) : formName;

		return _getValidationEngine().getJqueryValidateJs(
			ruleset = _getValidationRulesetFromFormName( validationFormName )
		);
	}

	public any function preProcessForm( required string formName, required struct formData ) {
		var formFields       = listFields( arguments.formName );
		var fieldValue       = "";
		var validationResult = _getValidationEngine().newValidationResult();

		for( var field in formFields ){
			fieldValue = arguments.formData[ field ] ?: "";
			if ( Len( fieldValue ) ) {
				try {
					arguments.formData[ field ] = preProcessFormField(
						  formName   = arguments.formName
						, fieldName  = field
						, fieldValue = fieldValue
					);
				} catch( any e ) {
					validationResult.addError(
						  fieldName = field
						, message   = e.message
					);
				}
			}
		}

		return validationResult;
	}

	public any function preProcessFormField( required string formName, required string fieldName, required string fieldValue ) {
		var field        = getFormField( formName = arguments.formName, fieldName = arguments.fieldName );
		var preProcessor = _getPreProcessorForField( argumentCollection = field );

		if ( Len( Trim( preProcessor ) ) ) {
			return _getColdbox().runEvent(
				  event          = preProcessor
				, prePostExempt  = true
				, private        = true
				, eventArguments = { fieldName=arguments.fieldName, preProcessorArgs=field }
			);
		}

		return arguments.fieldValue;
	}

	public string function getMergedFormName( required string formName, required string mergeWithFormName, boolean createIfNotExists=true ) {
		var mergedName = formName & ".merged.with." & mergeWithFormName;

		if ( createIfNotExists && !formExists( mergedName ) ) {
			mergeForms( formName, mergeWithFormName );
		}

		return mergedName;
	}

	public void function reload() {
		_loadForms();
	}

// PRIVATE HELPERS
	private void function _loadForms() {
		var dirs     = _getFormDirectories();
		var prefix   = "";
		var dir      = "";
		var formName = "";
		var files    = "";
		var file     = "";
		var subDir   = "";
		var forms    = {};
		var frm      = "";

		for( dir in dirs ) {
			dir = ExpandPath( dir );
			prefix = _getSiteTemplatePrefixForDirectory( dir );
			files = DirectoryList( dir, true, "path", "*.xml" );
			for( file in files ){
				formName = ReplaceNoCase( file, dir, "" );
				formName = ReReplace( formName, "\.xml$", "" );
				formName = ListChangeDelims( formName, ".", "\/" );

				if ( Len( Trim( prefix ) ) ) {
					formName = ListPrepend( formName, prefix, "." );
				}

				forms[ formName ] = forms[ formName ] ?: [];
				forms[ formName ].append( _readForm( filePath=file ) );
			}
		}

		_setForms( {} );
		for( formName in forms ) {
			frm = forms[ formName ][ 1 ];
			for( var i=2; i <= forms[ formName ].len(); i++ ) {
				frm = _mergeForms(
					  form1 = frm
					, form2 = forms[ formName ][ i ]
				);
			}
			if ( _registerForm( formName, frm ) ) {
				_applyDefaultLabellingToForm( formName );
			}
		}
	}

	private boolean function _registerForm( required string formName, required struct formDefinition ) {
		if ( _formDoesNotBelongToDisabledFeature( arguments.formDefinition ) ) {
			var forms   = _getForms();
			var ruleset = _getValidationEngine().newRuleset( name="PresideForm.#formName#" );

			forms[ formName ] = formDefinition;

			ruleset.addRules(
				rules = _getPresideFieldRuleGenerator().generateRulesFromPresideForm( formDefinition )
			);

			return true;
		}

		return false;
	}

	private struct function _readForm( required string filePath ) {
		var xml            = "";
		var tabs           = "";
		var theForm        = {};
		var formAttributes = {};

		try {
			xml = XmlParse( arguments.filePath );
		} catch ( any e ) {
			throw(
				  type = "FormsService.BadFormXml"
				, message = "The form definition file, [#ListLast( arguments.filePath, '\/' )#], does not contain valid XML"
				, detail = e.message

			);
		}

		formAttribs = xml.form.xmlAttributes ?: {};
		for( var key in formAttribs ){
			theForm[ key ] = formAttribs[ key ];
		}
		theForm.tabs = [];

		tabs = XmlSearch( xml, "/form/tab" );

		for ( var i=1; i lte ArrayLen( tabs ); i++ ) {
			var attribs = tabs[i].xmlAttributes;

			var tab = {
				  title       = attribs.title       ?: ""
				, description = attribs.description ?: ""
				, id          = attribs.id          ?: ""
				, fieldsets   = []
			}
			StructAppend( tab, attribs, false );

			if ( StructKeyExists( tabs[i], "fieldset" ) ) {
				for( var n=1; n lte ArrayLen( tabs[i].fieldset ); n++ ){
					attribs = tabs[i].fieldset[n].xmlAttributes;

					var fieldset = {
						  title       = attribs.title       ?: ""
						, description = attribs.description ?: ""
						, id          = attribs.id          ?: ""
						, fields      = []
					};
					StructAppend( fieldset, attribs, false );

					if ( StructKeyExists( tabs[i].fieldset[n], "field" ) ) {
						for( var x=1; x lte ArrayLen( tabs[i].fieldset[n].field ); x++ ){
							var field = {};

							for( var key in tabs[i].fieldset[n].field[x].xmlAttributes ){
								field[ key ] = Duplicate( tabs[i].fieldset[n].field[x].xmlAttributes[ key ] );
							}

							_bindAttributesFromPresideObjectField( field );
							field.rules = _parseRules( field = tabs[i].fieldset[n].field[x] );

							ArrayAppend( fieldset.fields, field );
						}
					}

					ArrayAppend( tab.fieldsets, fieldset );
				}
			}

			ArrayAppend( theForm.tabs, tab );
		}

		return theForm;
	}

	private void function _bindAttributesFromPresideObjectField( required struct field ) {
		var property    = "";
		var boundObject = "";
		var boundField  = "";
		var pobjService = "";

		if ( StructKeyExists( field, "binding" ) and Len( Trim( field.binding ) ) ) {
			if ( ListLen( field.binding, "." ) neq 2 ) {
				throw(
					  type    = "FormsService.MalformedBinding"
					, message = "The binding [#field.binding#] was malformed. Bindings should take the form, [presideObjectName.fieldName]"
				);
			}

			pobjService = _getPresideObjectService();
			boundField  = ListRest( field.binding, "." );
			boundObject = ListFirst( field.binding, "." );

			if ( not pobjService.objectExists( boundObject ) ) {
				throw(
					  type = "FormsService.BadBinding"
					, message = "The preside object, [#boundObject#], referred to in the form field binding, [#field.binding#], could not be found. Valid objects are #SerializeJson( pobjService.listObjects() )#"
				);
			}
			if ( not pobjService.fieldExists( boundObject, boundField ) ){
				throw(
					  type = "FormsService.BadBinding"
					, message = "The field, [#boundField#], referred to in the form field binding, [#field.binding#], could not be found in Preside Object, [#boundObject#]"
				);
			}

			property = _getPresideObjectService().getObjectProperty( boundObject, boundField ).getMemento();

			StructAppend( field, property, false );
			field.sourceObject = boundObject;
			if ( not StructKeyExists( field, "name" ) ) {
				field.name = boundField;
			}
		}
	}

	private array function _parseRules( required any field ) {
		var rules = [];
		var rule  = "";
		var newRule = "";
		var attr  = "";
		var param = "";
		var i     = "";
		var n     = "";

		if ( IsDefined( "arguments.field.rule" ) )  {
			for( i=1; i lte ArrayLen( arguments.field.rule ); i++ ){
				rule = arguments.field.rule[i];
				newRule = {};
				for( attr in rule.xmlAttributes ){
					newRule[ attr ] = Duplicate( rule.xmlAttributes[ attr ] );
				}

				newRule.params = {};

				if ( IsDefined( "rule.param" ) ) {
					for( n=1; n lte ArrayLen( rule.param ); n++ ){
						param = rule.param[n];
						newRule.params[ param.xmlAttributes.name ] = param.xmlAttributes.value;
					}
				}

				ArrayAppend( rules, newRule );
			}
		}

		return rules;
	}

	private string function _getPresideObjectNameFromFormNameByConvention( required string formName ) {
		if ( [ "page-types", "preside-objects" ].find( ListFirst( arguments.formName, "." ) ) and ListLen( arguments.formName, "." ) gt 1 ) {
			return ListGetAt( arguments.formName, 2, "." );
		}

		if ( ListFirst( arguments.formName, "." ) eq "" and ListLen( arguments.formName, "." ) gt 1 ) {
			return ListGetAt( arguments.formName, 2, "." );
		}

		return "";
	}

	private string function _getFormControlHandler( required string type, required string context ) {
		var configuredControls = _getConfiguredControls();
		var defaultContext     = _getDefaultContextName();

		if ( StructKeyExists( configuredControls, arguments.type ) ) {
			if ( IsSimpleValue( configuredControls[ arguments.type ] ) ) {
				return configuredControls[ arguments.type ];
			}
			if ( IsStruct( configuredControls[ arguments.type ] ) ) {
				if ( StructKeyExists( configuredControls[ arguments.type ], arguments.context ) ) {
					return configuredControls[ arguments.type ][ arguments.context ];
				}
				if ( StructKeyExists( configuredControls[ arguments.type ], defaultContext ) ) {
					return configuredControls[ arguments.type ][ defaultContext ];
				}
			}
		}

		if ( _getColdbox().viewletExists( "formcontrols.#arguments.type#.#arguments.context#" ) ) {
			return "formcontrols.#arguments.type#.#arguments.context#";
		}

		return "formcontrols.#arguments.type#.#defaultContext#";
	}

	private string function _getDefaultFormControl() {
		return _getPresideObjectService().getDefaultFormControlForPropertyAttributes( argumentCollection = arguments );
	}

	private string function _getValidationRulesetFromFormName( required string formName ) {
		var objectName = _getPresideObjectNameFromFormNameByConvention( arguments.formName );

		if ( formExists( arguments.formName, false ) ) {
			return "PresideForm.#arguments.formName#";
		}

		var siteTemplateFormName = _getSiteTemplatePrefix() & arguments.formName;
		if ( formExists( siteTemplateFormName, false ) ) {
			return "PresideForm.#siteTemplateFormName#";
		}

		if ( _getPresideObjectService().objectExists( objectName ) ) {
			return "PresideObject.#objectName#";
		}

		return "";
	}

	private struct function _getI18nFieldAttributes( required struct field ) {
		var i18n             = _getI18n();
		var fieldName        = arguments.field.name ?: "";
		var backupLabelUri   = "cms:preside-objects.default.field.#fieldName#.title";
		var fieldLabel       = arguments.field.label       ?: "";
		var fieldHelp        = arguments.field.help        ?: "";
		var fieldPlaceholder = arguments.field.placeholder ?: "";
		var attributes       = {};

		if ( Len( Trim( fieldLabel ) ) ) {
			if ( i18n.isValidResourceUri( fieldLabel ) ) {
				attributes.label = i18n.translateResource( uri=fieldLabel, defaultValue=i18n.translateResource( uri = backupLabelUri, defaultValue = fieldName ) );
			} else {
				attributes.label = fieldLabel;
			}
		} else {
			attributes.label = i18n.translateResource( uri = backupLabelUri, defaultValue = fieldName );
		}

		if ( Len( Trim( fieldHelp ) ) ) {
			if ( i18n.isValidResourceUri( fieldHelp ) ) {
				attributes.help = i18n.translateResource( uri=fieldHelp, defaultValue="" );
			} else {
				attributes.help = fieldHelp;
			}
		}

		if ( Len( Trim( fieldPlaceholder ) ) ) {
			if ( i18n.isValidResourceUri( fieldPlaceholder ) ) {
				attributes.placeholder = i18n.translateResource( uri=fieldPlaceholder, defaultValue="" );
			} else {
				attributes.placeholder = fieldPlaceholder;
			}
		}


		return attributes;
	}

	private struct function _getI18nTabOrFieldsetAttributes( required struct tabOrFieldset ) {
		var i18n       = _getI18n();
		var attributes = {};

		if ( Len( Trim( tabOrFieldset.title ?: "" ) ) ) {
			if ( i18n.isValidResourceUri( tabOrFieldset.title ) ) {
				attributes.title = i18n.translateResource( uri=tabOrFieldset.title, defaultValue="" );
			} else {
				attributes.title = tabOrFieldset.title;
			}
		}

		if ( Len( Trim( tabOrFieldset.description ?: "" ) ) ) {
			if ( i18n.isValidResourceUri( tabOrFieldset.description ) ) {
				attributes.description = i18n.translateResource( uri=tabOrFieldset.description, defaultValue="" );
			} else {
				attributes.description = tabOrFieldset.description;
			}
		}

		return attributes;
	}

	private string function _getPreProcessorForField( string preProcessor="", string control="" ) {
		var coldboxEvent = "";
		var coldbox      = _getColdbox();

		if ( Len( Trim( arguments.preProcessor ) ) ) {
			coldboxEvent = arguments.preProcessor;
		} else {
			if ( arguments.control eq "default" or not Len( Trim( arguments.control ) ) ) {
				coldboxEvent = _getDefaultFormControl( argumentCollection = arguments );
			} else {
				coldboxEvent = arguments.control;
			}
		}

		coldboxEvent = "preprocessors." & coldboxEvent;
		if ( coldbox.handlerExists( coldboxEvent ) ) {
			return coldboxEvent;
		}

		coldboxEvent = ListAppend( coldboxEvent, _getDefaultContextName(), "." );
		if ( coldbox.handlerExists( coldboxEvent ) ) {
			return coldboxEvent;
		}


		return "";
	}

	private struct function _mergeForms( required struct form1, required struct form2 ) {
		for( var tab in form2.tabs ){
			var matchingTab = {};
			if ( Len( Trim( tab.id ?: "" ) ) ) {
				for( var mTab in form1.tabs ){
					if ( ( mTab.id ?: "" ) == tab.id ) {
						matchingTab = mTab;
						break;
					}
				}
			}
			if ( StructIsEmpty( matchingTab ) ) {
				ArrayAppend( form1.tabs, tab );
				continue;
			} elseif ( IsBoolean( tab.deleted ?: "" ) and tab.deleted ) {
				ArrayDelete( form1.tabs, matchingTab );
				continue;
			}

			for( var fieldSet in tab.fieldSets ){
				var matchingFieldset = {};
				if ( Len( Trim( fieldSet.id ?: "" ) ) ) {
					for( var mFieldset in matchingTab.fieldsets ){
						if ( ( mFieldset.id ?: "" ) == fieldSet.id ) {
							matchingFieldset = mFieldset;
							break;
						}
					}
				}
				if ( StructIsEmpty( matchingFieldset ) ) {
					ArrayAppend( matchingTab.fieldsets, fieldset );
					continue;
				} elseif ( IsBoolean( fieldSet.deleted ?: "" ) and fieldSet.deleted ) {
					ArrayDelete( matchingTab.fieldSets, matchingFieldset );
					continue;
				}

				for( var field in fieldset.fields ) {
					var fieldMatched = false;
					var fieldDeleted = false;
					for( var mField in matchingFieldset.fields ){
						if ( mField.name == field.name ) {
							if ( IsBoolean( field.deleted ?: "" ) and field.deleted ) {
								ArrayDelete( matchingFieldset.fields, mField );
								fieldDeleted = true;
							} else {
								StructAppend( mField, field );
								fieldMatched = true;
								break;
							}
						}
					}
					if ( !fieldMatched && !fieldDeleted ) {
						ArrayAppend( matchingFieldset.fields, field );
					}
				}
				StructDelete( fieldset, "fields" );
				var autoFieldsetAttribs = fieldset.autoGeneratedAttributes ?: [];
				for( var attrib in fieldset ) {
					if ( IsSimpleValue( fieldset[ attrib ] ) && Len( Trim( fieldset[ attrib ] ) ) && ( !matchingFieldset.keyExists( attrib ) || !autoFieldsetAttribs.findNoCase( attrib ) ) ) {
						matchingFieldset[ attrib ] = fieldset[ attrib ];
					}
				}

				matchingFieldset.fields.sort( function( field1, field2 ){
					var order1 = Val( field1.sortOrder ?: 999999999 );
					var order2 = Val( field2.sortOrder ?: 999999999 );

					return order1 == order2 ? 0 : ( order1 > order2 ? 1 : -1 );
				} );
			}

			StructDelete( tab, "fieldsets" );
			var autoTabAttribs = tab.autoGeneratedAttributes ?: [];
			for( var attrib in tab ) {
				if ( IsSimpleValue( tab[ attrib ] ) && Len( Trim( tab[ attrib ] ) ) && ( !matchingTab.keyExists( attrib ) || !autoTabAttribs.findNoCase( attrib ) )  ) {
					matchingTab[ attrib ] = tab[ attrib ];
				}
			}

			matchingTab.fieldsets.sort( function( fieldset1, fieldset2 ){
				var order1 = Val( fieldset1.sortOrder ?: 999999999 );
				var order2 = Val( fieldset2.sortOrder ?: 999999999 );

				return order1 == order2 ? 0 : ( order1 > order2 ? 1 : -1 );
			} );
		}
		form1.tabs.sort( function( tab1, tab2 ){
			var order1 = Val( tab1.sortOrder ?: 999999999 );
			var order2 = Val( tab2.sortOrder ?: 999999999 );

			return order1 == order2 ? 0 : ( order1 > order2 ? 1 : -1 );
		} );

		return form1;
	}

	private string function _getSiteTemplatePrefixForDirectory( required string directory ) {
		var matchRegex = "^.*?site-templates[\\/]([^/]+)[\\/]forms.*$";

		if (  ReFindNoCase( matchRegex, arguments.directory ) ) {
			return "site-template::" & ReReplace( arguments.directory, matchRegex, "\1" );
		}

		return "";
	}

	private boolean function _formControlHasLayout( required string control ) {
		switch( arguments.control ){
			case "hidden":
				return false;
		}

		return true;
	}

	private string function _getSiteTemplatePrefix() {
		var siteTemplate = _getSiteService().getActiveSiteTemplate();
		return Len( Trim( siteTemplate ) ) ? ( "site-template::" & sitetemplate & "." ) : "";
	}

	private boolean function _formDoesNotBelongToDisabledFeature( required struct formDefinition ) {
		return !Len( Trim( formDefinition.feature ?: "" ) ) || _getFeatureService().isFeatureEnabled( Trim( formDefinition.feature ) );
	}

	private string function _getDefaultI18nBaseUriForForm( required string formName ) {
		if ( formExists( arguments.formName ) ) {
			var formConfig = getForm( arguments.formName );

			if ( Len( Trim( formConfig.i18nBaseUri ?: "" ) ) ) {
				return formConfig.i18nBaseUri;
			}
		}

		var presideObjectName = _getPresideObjectNameFromFormNameByConvention( arguments.formName );
		if ( Len( Trim( presideObjectName ) ) ) {
			var presideObjectName = _getPresideObjectService().getObjectAttribute( presideObjectName, "derivedFrom", presideObjectName );
			if ( _getPresideObjectService().getObjectAttribute( presideObjectName, "isPageType", false ) ) {
				return "page-types.#presideObjectName#:";
			}
			return "preside-objects.#presideObjectName#:";
		}

		return "";
	}

	private void function _applyDefaultLabellingToForm( required string formName, struct frm=getForm( arguments.formName ) ) {
		var baseI18nUri = _getDefaultI18nBaseUriForForm( arguments.formName );

		var tabs = frm.tabs ?: [];

		for( var tab in tabs ) {
			if ( Len( Trim( baseI18nUri ) ) ) {
				tab.autoGeneratedAttributes = [];
				if ( Len( Trim( tab.id ?: "" ) ) ) {
					if ( !Len( Trim( tab.title ?: "" ) ) ) {
						tab.title = baseI18nUri & "tab.#tab.id#.title";
						tab.autoGeneratedAttributes.append( "title" );
					}
					if ( !Len( Trim( tab.description ?: "" ) ) ) {
						tab.description = baseI18nUri & "tab.#tab.id#.description";
						tab.autoGeneratedAttributes.append( "description" );
					}
				}
			}
			var fieldsets = tab.fieldsets ?: [];
			for( var fieldset in fieldsets ) {
				if ( Len( Trim( baseI18nUri ) ) ) {
					fieldset.autoGeneratedAttributes = [];
					if ( Len( Trim( fieldset.id ?: "" ) ) ) {
						if ( !Len( Trim( fieldset.title ?: "" ) ) ) {
							fieldset.title = baseI18nUri & "fieldset.#fieldset.id#.title";
							fieldset.autoGeneratedAttributes.append( "title" );
						}
						if ( !Len( Trim( fieldset.description ?: "" ) ) ) {
							fieldset.description = baseI18nUri & "fieldset.#fieldset.id#.description";
							fieldset.autoGeneratedAttributes.append( "description" );
						}
					}
				}

				var fields = fieldset.fields ?: [];
				for( var field in fields ) {
					var fieldBaseI18n = "";
					if ( ListLen( field.binding ?: "", "." ) == 2 ) {
						var objName = ListFirst( field.binding, "." );
						if ( _getPresideObjectService().isPageType( objName ) ) {
							fieldBaseI18n = "page-types.#objName#:";
						} else {
							fieldBaseI18n = "preside-objects.#objName#:";
						}
					} else {
						fieldBaseI18n = baseI18nUri;
					}
					if ( Len( Trim( fieldBaseI18n ) ) && Len( Trim( field.name ?: "" ) ) ) {
						if ( !Len( Trim( field.label ?: "" ) ) ) {
							field.label = fieldBaseI18n & "field.#field.name#.title";
						}
						if ( !Len( Trim( field.placeholder ?: "" ) ) ) {
							field.placeholder = fieldBaseI18n & "field.#field.name#.placeholder";
						}
						if ( !Len( Trim( field.help ?: "" ) ) ) {
							field.help = fieldBaseI18n & "field.#field.name#.help";
						}
					}
				}
			}
		}
	}

// GETTERS AND SETTERS
	private array function _getFormDirectories() {
		return _formDirectories;
	}
	private void function _setFormDirectories( required array formDirectories ) {
		_formDirectories = arguments.formDirectories;
	}

	private any function _getPresideObjectService() {
		return _presideObjectService;
	}
	private void function _setPresideObjectService( required any presideObjectService ) {
		_presideObjectService = arguments.presideObjectService;
	}

	private struct function _getForms() {
		return _forms;
	}
	private void function _setForms( required struct forms ) {
		_forms = arguments.forms;
	}

	private any function _getValidationEngine() {
		return _validationEngine;
	}
	private void function _setValidationEngine( required any validationEngine ) {
		_validationEngine = arguments.validationEngine;
	}

	private any function _getI18n() {
		return _i18n;
	}
	private void function _setI18n( required any i18n ) {
		_i18n = arguments.i18n;
	}

	private any function _getColdBox() {
		return _coldBox;
	}
	private void function _setColdBox( required any coldBox ) {
		_coldBox = arguments.coldBox;
	}

	private string function _getDefaultContextName() {
		return _defaultContextName;
	}
	private void function _setDefaultContextName( required string defaultContextName ) {
		_defaultContextName = arguments.defaultContextName;
	}

	private struct function _getConfiguredControls() {
		return _configuredControls;
	}
	private void function _setConfiguredControls( required struct configuredControls ) {
		_configuredControls = arguments.configuredControls;
	}

	private any function _getPresideFieldRuleGenerator() {
		return _presideFieldRuleGenerator;
	}
	private void function _setPresideFieldRuleGenerator( required any presideFieldRuleGenerator ) {
		_presideFieldRuleGenerator = arguments.presideFieldRuleGenerator;
	}

	private any function _getFeatureService() {
		return _featureService;
	}
	private void function _setFeatureService( required any featureService ) {
		_featureService = arguments.featureService;
	}

	private any function _getSiteService() {
		return _siteService;
	}
	private void function _setSiteService( required any siteService ) {
		_siteService = arguments.siteService;
	}
}