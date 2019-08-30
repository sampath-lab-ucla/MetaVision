classdef primary < MetaVision.ui.UIContainer
  %primary Displays metadata information attached to each open file.
  events
    loadFile
    loadDirectory
    requestAbout
    requestSupportedFiles
  end
  
  % Properties that correspond to app components
  properties (Access = public)
    FileTree        matlab.ui.container.Tree
    FileMenu            matlab.ui.container.Menu
    OpenFileMenu        matlab.ui.container.Menu
    OpenDirectoryMenu   matlab.ui.container.Menu
    HelpMenu            matlab.ui.container.Menu
    SupportedFilesMenu  matlab.ui.container.Menu
    AboutMenu           matlab.ui.container.Menu
    PropNodes    
    PropTable       matlab.ui.control.Table
  end
  properties (Constant = true)
    TREE_MAX_WIDTH = 300 %Maximum uitree panel width in pixels.
    TREE_MIN_WIDTH = 80  %Minimum uitree panel width in pixels.
  end
  properties (Dependent)
    isclear
    hasnodes
  end
  %% Public methods
  methods
    
    function buildUI(obj,varargin)
      if nargin < 2, return; end
      if obj.isClosed, obj.rebuild(); end
      
      obj.clearView;
      
      obj.show;
      files = [varargin{:}];
      obj.PropNodes = {};
      obj.recurseInfo(files, 'File', obj.FileTree);
    end
    
    function tf = get.isclear(obj)
      tf = isempty(obj.PropTable.Data);
    end
    
    function tf = get.hasnodes(obj)
      tf = ~isempty(obj.PropNodes);
    end
    
  end
  %% Startup and Callback Methods
  methods (Access = protected)
    
    % Startup
    function startupFcn(obj,varargin)
      if nargin < 2, return; end
      obj.buildUI(varargin{:});
    end
    
    % Recursion
    function recurseInfo(obj, S, name, parentNode)
      for f = 1:length(S)
        if iscell(S)
          this = S{f};
        else
          this = S(f);
        end
        props = fieldnames(this);
        vals = struct2cell(this);
        %find nests
        notNested = cellfun(@(v) ~isstruct(v),vals,'unif',1);
        if ~isfield(this,'File')
          hasName = contains(lower(props),'name');
          if any(hasName)
            nodeName = sprintf('%s (%s)',vals{hasName},name);
          else
            nodeName = sprintf('%s %d', name, f);
          end
        else
          nodeName = this.File;
        end
        thisNode = uitreenode(parentNode, ...
          'Text', nodeName );
        if any(notNested)
          thisNode.NodeData = [props(notNested),vals(notNested)];
        else
          thisNode.NodeData = [{},{}];
        end
        obj.PropNodes{end+1} = thisNode;
        %gen nodes
        if ~any(~notNested), continue; end
        isNested = find(~notNested);
        for n = 1:length(isNested)
          nestedVals = vals{isNested(n)};
          % if the nested values is an empty struct, don't create a node.
          areAllEmpty = all( ...
            arrayfun( ...
              @(sss)all( ...
                cellfun( ...
                  @isempty, ...
                  struct2cell(sss), ...
                  'UniformOutput', 1 ...
                  ) ...
                ), ...
              nestedVals, ...
              'UniformOutput', true ...
              ) ...
            );
          if areAllEmpty, continue; end
          obj.recurseInfo(nestedVals,props{isNested(n)},thisNode);
        end
      end
    end
    
    % Set Table Data
    function setData(obj,d)
      d(:,2) = arrayfun(@unknownCell2Str,d(:,2),'unif',0);
      obj.PropTable.Data = d;
      lens = cellfun(@length,d(:,2),'UniformOutput',true);
      tWidth = obj.PropTable.Position(3)-127;
      obj.PropTable.ColumnWidth = {125, max([tWidth,max(lens)*6.55])};
    end
    
    
    % Construct view
    function createUI(obj)
      import MetaVision.app.*;
      
      pos = obj.position;
      if isempty(pos)
        initW = 616;
        initH = 366;
        pos = centerFigPos(initW,initH);
      end
      obj.position = pos; %sets container too
      w = pos(3);
      h = pos(4);
      
      treeW = min([floor(w*0.33),obj.TREE_MAX_WIDTH]);
      if treeW < obj.TREE_MIN_WIDTH
        treeW = obj.TREE_MIN_WIDTH;
      end
      % Create container
      obj.container.Name = sprintf('%s v%s',Info.name,Info.version('major'));
      obj.container.SizeChangedFcn = @obj.containerSizeChanged;
      obj.container.Resize = 'on';
      
      % Create FileMenu
      obj.FileMenu = uimenu(obj.container);
      obj.FileMenu.Text = 'File';

      % Create OpenFileMenu
      obj.OpenFileMenu = uimenu(obj.FileMenu);
      obj.OpenFileMenu.Accelerator = 'O';
      obj.OpenFileMenu.Text = 'Open File...';
      obj.OpenFileMenu.MenuSelectedFcn = @(s,e)notify(obj,'loadFile');

      % Create OpenDirectoryMenu
      obj.OpenDirectoryMenu = uimenu(obj.FileMenu);
      obj.OpenDirectoryMenu.Accelerator = 'D';
      obj.OpenDirectoryMenu.Text = 'Open Directory...';
      obj.OpenDirectoryMenu.MenuSelectedFcn = @(s,e)notify(obj,'loadDirectory');
      
      % Create HelpMenu
      obj.HelpMenu = uimenu(obj.container);
      obj.HelpMenu.Text = 'Help';

      % Create SupportedFilesMenu
      obj.SupportedFilesMenu = uimenu(obj.HelpMenu);
      obj.SupportedFilesMenu.Text = 'Supported Files...';
      obj.SupportedFilesMenu.MenuSelectedFcn = @(s,e)notify(obj,'requestSupportedFiles');
      
      % Create AboutMenu
      obj.AboutMenu = uimenu(obj.HelpMenu);
      obj.AboutMenu.Text = 'About';
      obj.AboutMenu.MenuSelectedFcn = @(s,e)notify(obj,'requestAbout');
      
      % Create FileTree
      obj.FileTree = uitree(obj.container);
      obj.FileTree.FontName = 'Times New Roman';
      obj.FileTree.FontSize = 16;
      obj.FileTree.Multiselect = 'off';
      obj.FileTree.SelectionChangedFcn = @obj.getSelectedInfo;

      % Create PropTable
      obj.PropTable = uitable(obj.container);
      obj.PropTable.ColumnName = {'Property'; 'Value'};
      obj.PropTable.ColumnWidth = {125, 'auto'};
      obj.PropTable.RowName = {};
      obj.PropTable.HandleVisibility = 'off';
      
      obj.FileTree.Position = [10, 10, treeW, h-10-10];
      obj.PropTable.Position = [treeW+8+10, 10, w-treeW-7-10-10, h-10-10];
    end
    
    % Destruct View
    function clearView(obj)
      if obj.hasnodes
        cellfun(@delete,obj.PropNodes,'UniformOutput',false);
      end
      if ~obj.isclear
        obj.PropTable.Data = {[],[]};
      end
    end
    
  end
  
  %% Callback
  methods (Access = private)
    
    % Size changed function: container
    function containerSizeChanged(obj,~,~)
      pos = obj.container.Position;
      w = pos(3);
      h = pos(4);
      treeW = min([floor(w*0.33),obj.TREE_MAX_WIDTH]);
      if treeW < obj.TREE_MIN_WIDTH
        treeW = obj.TREE_MIN_WIDTH;
      end
      obj.FileTree.Position = [10 10 treeW h-10-10];
      obj.PropTable.Position = [treeW+8+10, 10, w-treeW-7-10-10, h-10-10];
      lens = cellfun(@length,obj.PropTable.Data(:,2),'UniformOutput',true);
      tWidth = obj.PropTable.Position(3)-127;
      obj.PropTable.ColumnWidth = {125, max([tWidth,max(lens)*6.55])};
    end
    
    % Selection Node changed.
    function getSelectedInfo(obj,~,evt)
      if ~isempty(evt.SelectedNodes)
        obj.setData(evt.SelectedNodes.NodeData);
      else
        obj.setData({[],[]});
      end
    end
    
    
  end
  %% Preferences
  methods (Access = protected)

   function setContainerPrefs(obj)
      setContainerPrefs@MetaVision.ui.UIContainer(obj);
    end
    
    function getContainerPrefs(obj)
      getContainerPrefs@MetaVision.ui.UIContainer(obj);
    end
    
  end
end