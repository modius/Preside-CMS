component extends="preside.system.base.AdminHandler" {

	property name="notificationService" inject="notificationService";
	property name="messageBox"          inject="coldbox:plugin:messageBox";

	public void function preHandler( event ) {
		super.preHandler( argumentCollection=arguments );

		prc.pageIcon = "fa-bell";
		event.addAdminBreadCrumb(
			  title = translateResource( "cms:notifications.breadcrumbTitle" )
			, link  = event.buildAdminLink( linkTo="notifications" )
		);
	}

	public void function index( event, rc, prc ) {
		prc.pageTitle    = translateResource( "cms:notifications.page.title" );
		prc.pageSubTitle = translateResource( "cms:notifications.page.subtitle" );

	}

	public void function getNotificationsForAjaxDataTables( event, rc, prc ) {
		var topic               = ( rc.topic ?: "" )
		var checkboxCol         = [];
		var optionsCol          = [];
		var gridFields          = [ "data", "datecreated" ];
		var dtHelper            = getMyPlugin( "JQueryDatatablesHelpers" );
		var totalNotifications  = notificationService.getNotificationsCount(
			  userId = event.getAdminUserId()
			, topic  = topic
		);
		var notifications       = notificationService.getNotifications(
			  userId      = event.getAdminUserId()
			, topic       = topic
			, startRow    = dtHelper.getStartRow()
			, maxRows     = dtHelper.getMaxRows()
			, orderBy     = dtHelper.getSortOrder()
			, searchQuery = dtHelper.getSearchQuery()
		);

		for( var record in notifications ){
			notifications.data[ notifications.currentRow ]        = renderNotification( topic=record.topic, data=record.data, context='datatable' );
			notifications.datecreated[ notifications.currentRow ] = renderField( object="admin_notification", property="datecreated", data=record.datecreated, context=[ "datatable", "admin" ] );

			ArrayAppend( checkboxCol, renderView( view="/admin/datamanager/_listingCheckbox", args={ recordId=record.id } ) );
			ArrayAppend( optionsCol, renderView( view="/admin/notifications/_listingGridActions", args=record ) );
		}

		QueryAddColumn( notifications, "_checkbox", checkboxCol );
		ArrayPrepend( gridFields, "_checkbox" );
		QueryAddColumn( notifications, "_options" , optionsCol );
		ArrayAppend( gridFields, "_options" );

		event.renderData( type="json", data=dtHelper.queryToResult( notifications, gridFields, totalNotifications ) );
	}

	public void function view( event, rc, prc ) {
		prc.notification = notificationService.getNotification( id=rc.id ?: "" );
		if ( !prc.notification.count() ) {
			setNextEvent( url=event.buildAdminLink( linkTo="notifications" ) );
		}
		notificationService.markAsRead( [ rc.id ], event.getAdminUserId() );

		prc.pageTitle    = translateResource( uri="cms:notifications.view.title" );
		prc.pageSubTitle = translateResource( uri="cms:notifications.view.subtitle", data=[ renderContent( "datetime", prc.notification.datecreated ) ] );

		event.addAdminBreadCrumb(
			  title = translateResource( "cms:notifications.view.breadcrumbTitle" )
			, link  = event.buildAdminLink( linkTo="notifications.view", queryString="id=" & rc.id )
		);
	}

	public void function readAction( event, rc, prc ) {
		var notifications = ListToArray( rc.id ?: "" );

		if ( notifications.len() ) {
			notificationService.markAsRead( notifications, event.getAdminUserId() );
		}

		setNextEvent( url=event.buildAdminLink( linkTo="notifications" ) );
	}

	public void function dismissAction( event, rc, prc ) {
		var notifications = ListToArray( rc.id ?: "" );

		if ( notifications.len() ) {
			notificationService.dismiss( notifications );
		}

		setNextEvent( url=event.buildAdminLink( linkTo="notifications" ) );
	}

	public void function multiAction( event, rc, prc ) {
		switch( rc.multiAction ?: "read" ) {
			case "dismiss":
				dismissAction( argumentCollection=arguments );
				break;
			default:
				readAction( argumentCollection=arguments );
		}
	}

	public void function preferences( event, rc, prc ) {

		prc.pageTitle    = translateResource( uri="cms:notifications.preferences.title" );
		prc.pageSubTitle = translateResource( uri="cms:notifications.preferences.subtitle" );

		event.addAdminBreadCrumb(
			  title = translateResource( "cms:notifications.preferences.breadcrumbTitle" )
			, link  = event.buildAdminLink( linkTo="notifications.preferences" )
		);

		prc.subscriptions = notificationService.getUserSubscriptions( userId=event.getAdminUserId() );
		prc.topics        = notificationService.listTopics();

		var isTopicForm = Len( Trim( rc.topic ?: "" ) );
		if ( isTopicForm ) {
			prc.subscription = notificationService.getUserTopicSubscriptionSettings( userId=event.getAdminUserId(), topic=rc.topic );
			if ( prc.subscription.isEmpty() && !prc.subscriptions.find( "all" ) ) {
				setNextEvent( url=event.buildAdminLink( linkTo="notifications.preferences" ) );
			}
		}
	}

	public void function savePreferencesAction( event, rc, prc ) {
		notificationService.saveUserSubscriptions(
			  userId = event.getAdminUserId()
			, topics = ListToArray( rc.subscriptions ?: "" )
		);

		messageBox.info( translateResource( uri="cms:notifications.preferences.saved.confirmation" ) );

		setNextEvent( url=event.buildAdminLink( linkTo="notifications.preferences" ) );
	}

	public void function saveTopicPreferencesAction( event, rc, prc ) {
		var formName = "notifications.topic-preferences";
		var formData = event.getCollectionForForm( formName );
		var validationResult = validateForm( formName=formName, formData=formData );
		var topic = rc.topic ?: "";

		if ( validationResult.validated() ) {
			notificationService.saveUserTopicSubscriptionSettings(
				  userId   = event.getAdminUserId()
				, topic    = rc.topic
				, settings = formData
			);

			messageBox.info( translateResource( uri="cms:notifications.preferences.saved.confirmation" ) );
			setNextEvent( url=event.buildAdminLink( linkTo="notifications.preferences", queryString="topic=#topic#" ) );
		} else {
			messageBox.error( translateResource( uri="cms:notifications.preferences.saving.error" ) );
			setNextEvent( url=event.buildAdminLink( linkTo="notifications.preferences", queryString="topic=#topic#" ), persistStruct={ validationResult=validationResult } );
		}

	}

	public void function configure( event, rc, prc ) {
		_checkPermission( "configure", event );

		prc.pageTitle    = translateResource( uri="cms:notifications.configure.title" );
		prc.pageSubTitle = translateResource( uri="cms:notifications.configure.subtitle" );

		event.addAdminBreadCrumb(
			  title = translateResource( "cms:notifications.configure.breadcrumbTitle" )
			, link  = event.buildAdminLink( linkTo="notifications.configure" )
		);

		prc.topics = notificationService.listTopics();
		if ( prc.topics.len() ) {
			prc.selectedTopic = rc.topic ?: prc.topics[1];
			prc.topicConfiguration = notificationService.getGlobalTopicConfiguration( prc.selectedTopic );
		}
	}

	public void function saveTopicConfigurationAction( event, rc, prc ) {
		_checkPermission( "configure", event );

		var topic            = rc.topic ?: "";
		var formName         = "notifications.topic-global-config";
		var formData         = event.getCollectionForForm( formName );
		var validationResult = validateForm( formName, formData );

		if ( validationResult.validated() ) {
			notificationService.saveGlobalTopicConfiguration( topic, formData );
			messageBox.info( translateResource( uri="cms:notifications.configuration.saved.confirmation" ) );
			setNextEvent( url=event.buildAdminLink( linkTo="notifications.configure", queryString="topic=#topic#" ) );
		}

		messageBox.error( translateResource( uri="cms:notifications.configuration.saving.error" ) );
		var persist = formData;
		    persist.validationResult = validationResult;
		setNextEvent( url=event.buildAdminLink( linkTo="notifications.configure", queryString="topic=#topic#" ), persistStruct=persist );
	}

// VIEWLETS
	private string function notificationNavPromo( event, rc, prc, args={} ) {
		args.notificationCount   = notificationService.getUnreadNotificationCount( userId = event.getAdminUserId() );
		args.latestNotifications = notificationService.getUnreadTopics( userId = event.getAdminUserId() );

		return renderView( view="/admin/notifications/notificationNavPromo", args=args );
	}

// HELPERS
	private void function _checkPermission( required string permission, required any event ) {
		if ( !hasCmsPermission( "notifications.#arguments.permission#" ) ) {
			event.adminAccessDenied();
		}
	}
}