function [Data,Meta,Notes] = readSymphonyFile(fileName)
  % get h5 info
  info = h5info(fileName);
  % Check symphony version
  attList = [{info.Attributes.Name}',{info.Attributes.Value}'];
  symphonyVersion = attList{strcmpi(attList(:,1), 'version'),2};

  if symphonyVersion < 2
    %symphony v1
    Notes = getNotesV1();
    Meta = getMetaV1();
    Data = getDataV1();
  else
    %symphony v2
    Notes = getNotesV2();
    Meta = arrayfun(@getMetaV2, info.Groups, 'UniformOutput', 0);
    Meta = cat(1, Meta{:});
    Data = arrayfun(@getDataV2, info.Groups, 'UniformOutput', 0);
    Data = cat(1,Data{:});
  end
% return from here
%%% FUNCTIONS -------------------------------------------------------->

%% Version 1
function Notes = getNotesV1()
  %load the xml file
  [root,name,~] = fileparts(fileName);
  Notes = cell(1,2);
  try
    xmlFile = search_recurse([name,'_metadata'], 'root', root, 'ext', {'.xml'});
  catch 
    return;
  end
  Notes = XML2Notes(xmlFile);
end %notes

function Meta = getMetaV1()
  Meta = struct();
  % cellProperties = info.Groups.Groups;
  % cellAttributes = cellProperties(3).Attributes; % XXX indexing issue?
  % numerical index values, derived from cellAttributes(1:3).Name
  % 1. SourceID (i.e., 'WT')
  % 2. cellID (but we'll use fileName instead)
  % 3. rigName (which never changes and isn't used - omit until a problem occurs)

  rootName = info.Groups.Name;
  % /properties, /epochs, /epochGroups
  % Gather some manual information from groups
  tmp = cell2struct(...
    {info.Groups(end).Attributes(ismember({info.Groups(end).Attributes.Name}', ...
                                          {'label','keywords'})).Value, ...
     info.Groups(end).Groups(3).Attributes(...
       ismember({info.Groups(end).Groups(3).Attributes.Name}', ...
                'sourceID')).Value...
    }', ...
    {info.Groups(end).Attributes(ismember({info.Groups(end).Attributes.Name}', ...
                                          {'label','keywords'})).Name, ...
     info.Groups(end).Groups(3).Attributes(...
       ismember({info.Groups(end).Groups(3).Attributes.Name}', ...
                'sourceID')).Name...
    }');
  Meta.Label = tmp.label;
  % Keywords from file
  try
    Meta.Keywords = tmp.keywords;
  catch
    Meta.Keywords = '';
  end
  % Source ID
  Meta.SourceID = tmp.sourceID;
  % user-chosen identifier for the cell
  Meta.FullFile = fileName;
  % XXX hard-code now, get from user later
  Meta.CellType = 'unknown'; 
  % Additional properties
  Meta.ExperimentStartTime = sec2str( ...
    double(h5readatt(fileName, ...
      rootName, ...
      'startTimeDotNetDateTimeOffsetUTCTicks' ...
    ))*1e-7 ...
    );
  Meta.cellID = h5readatt(fileName, [rootName,'/properties'], 'cellID');
 
  % XXX hard-code now, get from user later
  Meta.OutputConfiguration = {'amp'; 'red'; 'orange'; 'blue'}; 
  % XXX hard-code now, get from user later
  Meta.OutputScaleFactor = {0; 19.3000; 30; 21}; 
  % XXX hard-code now, get from user later
  Meta.NDFConfiguration = {0; 0; 0; 0}; 
  % this is necessary for analysis program
  Meta.FamilyCondition.Label = {'Label'}; 
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.FamilyStepGuide = {'StmAmp'}; 
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.FamilyCueGuide = []; 
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.SegNum = 0;
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.PlotPref = 1;
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.ScaleFactorIndex = [];
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.DecimatePts = 1;
  % ??, copied from Kate's example CellInfo struct
  Meta.FamilyCondition.UserInfo = [];
  
end %meta
function Data = getDataV1()
  epochLocation = arrayfun( ...
    @(x)x.Groups(contains({x.Groups.Name}','/epochs')).Groups, ...
    info.Groups, ...
    'UniformOutput', 0 ...
    );
  epochLocation = cat(1,epochLocation{:});
  nEpochs = length(epochLocation);
  Data(nEpochs,1) = struct( ...
    'protocols', {{}}, ...
    'displayProperties', {{}}, ...
    'id', '', ...
    'responses', struct() ...
    );
  for epNum = 1:nEpochs
    curEpoch = epochLocation(epNum);
    curNames = {curEpoch.Groups.Name}';
    protos = find(contains(curNames, '/protocolParameters'),1);
    resps = find(contains(curNames, '/responses'),1);
    stims = find(contains(curNames, '/stimuli'),1);
    
    % Protocols
    Data(epNum,1).protocols = ...
      [ ...
        {curEpoch.Groups(protos).Attributes.Name}', ...
        {curEpoch.Groups(protos).Attributes.Value}' ...
      ];
    try
      Data(epNum,1).protocols( ...
        contains(Data(epNum,1).protocols(:,1), 'gitHash'), ...
        : ...
        ) = []; %drop gitHas if it's there.
    catch
    end
    dt = strsplit(Data(epNum,1).protocols{ ...
      contains(Data(epNum,1).protocols(:,1), 'dateAndTime'), ...
      2 ...
      }, ' ');
    Data(epNum,1).protocols( ...
      ismember(Data(epNum,1).protocols(:,1), 'dateAndTime'), ...
      : ...
      ) = [];
    Data(epNum,1).protocols = [ ...
      Data(epNum,1).protocols; ...
      {'Date', dt{1}; 'epochStartTime',  dt{2}} ...
      ];
    % Display
    
    % Responses
    responseData = struct( ...
      'sampleRate', {{}}, ...
      'duration', {{}}, ...
      'units', {{}}, ...
      'device', {{}}, ...
      'x', {{}}, ...
      'y', {{}} ...
      );
    responseData.responseConfiguration = struct( ...
      'deviceName', '', ...
      'configSettings', struct('name', '', 'value', {{}}) ...
      );
    nDevices = length(curEpoch.Groups(resps).Groups);
    for devNum = 1:nDevices
      curDev = curEpoch.Groups(resps).Groups(devNum);
      responseData.devices{devNum} = h5readatt(fileName, ...
        curDev.Name, ...
        'deviceName' ...
        );
      fs = h5readatt(fileName, ...
        curDev.Name, ...
        'sampleRate' ...
        );
      responseData.sampleRate{devNum} = fs;
      d = h5read(fileName, [curDev.Name,'/data']);
      dur = length(d.quantity(:))/fs;
      responseData.duration{devNum} = dur;
      responseData.x{devNum} = linspace(0,dur-1/fs, dur*fs)';
      responseData.y{devNum} = d.quantity;
      responseData.units(devNum) = unique(cellstr(d.unit'));
    end
    nStims = length(curEpoch.Groups(stims).Groups);
    for stimNum = 1:nStims
      curStim = curEpoch.Groups(stims).Groups(stimNum);
      currentDeviceName = h5readatt(fileName, curStim.Name, 'deviceName');
      responseData.responseConfiguration(stimNum).deviceName = currentDeviceName;
      try
        configInfo = h5info(fileName, ...
          sprintf( ...
            '%s/dataConfigurationSpans/span_0/%s', ...
            curStim.Name, ...
            currentDeviceName ...
          ) ...
          );
      catch
        continue;
      end
      nConfigs = length(configInfo.Attributes);
      for cf = 1:nConfigs
        responseData.responseConfiguration(stimNum).configSettings(cf).name = ...
          configInfo.Attributes(cf).Name;
        responseData.responseConfiguration(stimNum).configSettings(cf).value = ...
          {configInfo.Attributes(cf).Value};
      end
    end
    % get device configs
    responseData.deviceConfiguration = struct( ...
      'deviceName', '', ...
      'configSettings', struct('name', '', 'value', {{}}) ...
      );
    %
    Data(epNum,1).responses = responseData;
    
  end
  % reorder Data structs to get something resembling order
  [~,sortInds] = sort(...
    arrayfun( ...
      @(e) e.protocols{ismember(e.protocols(:,1), 'epochStartTime'),2}, ...
    Data, ...
    'UniformOutput', 0 ...
    ) ...
    );
  Data = Data(sortInds);
end %data
%% Version 2
function Notes = getNotesV2()
  nfo = info.Groups;
  %source notes
  sourceIndex = contains({nfo.Groups.Name}', '/sources');
  sourceGroups = nfo.Groups(sourceIndex); 
  sourceNotes(1:numel(sourceGroups.Groups),1) = struct('time',{''},'text',{''});
  if numel(sourceNotes) > 0
    for g = 1:numel(sourceGroups.Groups)
      try
        data = h5read(fileName,[sourceGroups.Groups(g).Name,'/notes']);
      catch
        continue
      end
      [~,sourceNotes(g).time] = sec2str(double(data.time.ticks)*1e-7);
      sourceNotes(g).text = data.text;
    end
  end

  %epochGroup notes
  groupIndex = ~cellfun(@isempty,...
    strfind({nfo.Groups.Name}', '/epochGroups'),'unif',1); %#ok
  epochGroups = nfo.Groups(groupIndex);
  blockNotes = struct('time',{''},'text',{''});
  if numel(epochGroups.Groups) > 0 
    % first get from group
    epochNotes = getNoteStruct({epochGroups.Groups.Name}');
    % then look for each experiment
    for g = 1:numel(epochGroups.Groups)
      epochBlockIndex = ~cellfun(@isempty,...
        strfind({epochGroups.Groups(g).Groups.Name}', '/epochBlocks'),'unif',1); %#ok
      epochBlocks = epochGroups.Groups(g).Groups(epochBlockIndex);
      % get each experiment for this epoch block
      blockNotes = [blockNotes;getNoteStruct({epochBlocks.Groups.Name}')];%#ok<AGROW>
    end
  end

  Notes = cat(2,...
      cat(1,... %add times
        sourceNotes.time, ...
        epochNotes.time, ...
        blockNotes.time ...
      ),...
      cat(1,... %add note texts
        sourceNotes.text, ...
        epochNotes.text, ...
        blockNotes.text ...
      )...
    );
  if ~numel(Notes)
    Notes = [{''},{''}];
    return
  end
  [~,sid] = sort(Notes(:,1));
  Notes = Notes(sid,:);
  
  % HELPER FXN
  function nStruct = getNoteStruct(loc)
    if ~iscell(loc)
      loc = cellstr(loc);
    end
    nStruct(1:numel(loc),1) = struct('time',{''},'text',{''});
    for g = 1:numel(loc)
      try
        notedata = h5read(fileName,[loc{g},'/notes']);
      catch
        continue
      end
      [~,nStruct(g).time] = sec2str(double(notedata.time.ticks)*1e-7);
      nStruct(g).text = notedata.text;
    end
  end
end %notes  
function Meta = getMetaV2(grp)
  % grp is the hdf5 location of the current experiment. If you run multiple
  % 'experiment' types (Our version is is called "Electrophysiology"
  [root,label,ext] = fileparts(fileName);
  % fing group's properties
  prpIndex = contains({grp.Groups.Name}', '/properties');
  Meta = cell2struct(...
    [ ...
      { ...
        [label,ext]; ...
        root ...
      }; ...
      { ...
        grp.Groups(prpIndex).Attributes.Value ...
      }' ...
    ], ...
    [ ...
      {'File';'Location'}; ...
      {grp.Groups(prpIndex).Attributes.Name}' ...
    ] ...
    );
  Meta.StartTime = ...
    sec2str(...
      double(...
        h5readatt(...
          fileName,...
          grp.Name,...
          'startTimeDotNetDateTimeOffsetTicks' ...
        ) ...
      ) * 1e-7 ...
    );
  Meta.EndTime = ...
    sec2str(...
      double(...
        h5readatt(...
          fileName,...
          grp.Name,...
          'endTimeDotNetDateTimeOffsetTicks' ...
        ) ...
      ) * 1e-7 ...
    );
  Meta.Purpose = h5readatt(fileName,grp.Name,'purpose');
  Meta.SymphonyVersion = h5readatt(fileName,info.Name,'symphonyVersion');
  % devices
  prpIndex = contains({grp.Groups.Name}', '/devices');
  deviceInfo = grp.Groups(prpIndex).Groups;
  nDevices = length(deviceInfo);
  %Meta.Devices = cell(1,nDevices);
  Meta.Devices = struct( ...
    'Name', '', ...
    'Manufacturer', '', ...
    'Resources', struct('name', '', 'value', []) ...
    );
  for deviceNum = 1:nDevices
    curName = deviceInfo(deviceNum).Name;
    tmpStr = struct();
    try
      tmpStr.Name = h5readatt(fileName,curName,'name');
    catch
      tmpStr.Name = sprintf('Device_%d',deviceNum);
    end
    
    try
      tmpStr.Manufacturer = h5readatt(fileName,curName,'manufacturer');
    catch
      tmpStr.Manufacturer = 'Unknown';
    end
    % add Resources here once I figure out how to capture them
    try
      resourceInfo = h5info(fileName,[curName,'/resources']);
      resourceTypes = arrayfun( ...
        @(rc) h5readatt(fileName,rc.Name,'name'), ...
        resourceInfo.Groups, ...
        'UniformOutput', 0 ...
        );
      % drop configuration settings as they require symphony installed on the
      % analysis computer.. eff-that.
      resourceInfo = resourceInfo.Groups( ...
        ~ismember(resourceTypes,'configurationSettingDescriptors') ...
        );
      resourceTypes = resourceTypes( ...
        ~ismember(resourceTypes,'configurationSettingDescriptors') ...
        );
      for g = 1:length(resourceInfo)
        rData = getArrayFromByteStream(h5read(fileName,[resourceInfo(g).Name,'/data']));
        tmpStr.Resources(g) = struct( ...
          'name', resourceTypes{g}, ...
          'value', rData ...
          );
      end
    catch
      tmpStr.Resources = struct('name', '', 'value', []);
    end
    if ~isfield(tmpStr,'Resources')
      tmpStr.Resources = struct('name', '', 'value', []);
    end
    Meta.Devices(deviceNum) = tmpStr;
  end
  prpIndex = contains({grp.Groups.Name}', '/sources');
  sourceLinks = grp.Groups(prpIndex).Links;
  sources = arrayfun( ...
    @(lnk)h5info(fileName,lnk.Value{1}), ...
    sourceLinks, ...
    'UniformOutput', 0 ...
    );
  nSources = length(sources);
  %Meta.Sources = cell(1,nSources);
  for sNum = 1:nSources
    curSource = sources{sNum};
    curName = sources{sNum}.Name;
    label = {h5readatt(fileName,curName,'label')};
    sourceAttr = curSource.Groups( ...
      contains({curSource.Groups.Name}','/source/properties') ...
      ).Attributes;
    Meta.Sources(sNum) = struct( ...
      'Name', label, ...
      'Properties', cell2struct({sourceAttr.Value}',{sourceAttr.Name}') ...
      );
    
    %{
    cell2struct( ...
      [label;{sourceAttr.Value}'], ...
      [{'Name'};{sourceAttr.Name}'] ...
      );
    %}
  end
  Meta.Label = label;
end
function Data = getDataV2(grp)
  epochGroups = grp.Groups(contains({grp.Groups.Name}', '/epochGroups'));
  blockPropGroups = arrayfun( ...
    @(g)g.Groups(contains({g.Groups.Name}','/properties')), ...
    epochGroups.Groups, ...
    'UniformOutput', 0 ...
    );
  blockProps = cellfun( ...
    @(blk) orderfields(cell2struct(...
      {blk.Attributes.Value}', ...
      matlab.lang.makeValidName({blk.Attributes.Name}') ...
      )), ...
    blockPropGroups, ...
    'UniformOutput', 0 ...
    );
  groupNames = arrayfun( ...
    @(grp) h5readatt(fileName,grp.Name, 'label'), ...
    epochGroups.Groups, ...
    'UniformOutput', 0 ...
    );
  for gp = 1:numel(blockProps)
    blockProps{gp}.Label= groupNames{gp};
  end
  % Get the protocol Block
  protocolBlocks = arrayfun( ...
    @(a) a.Groups( ...
      contains({a.Groups.Name}','/epochBlocks') ...
      ).Groups, ...
    epochGroups.Groups, ...
    'UniformOutput', 0 ...
    );
  protocolBlocks = cat(1,protocolBlocks{:});
  [protocolStartTime,protocolOrder] = sort(arrayfun( ...
    @(e) sec2str(double( ...
      h5readatt(fileName, e.Name, 'startTimeDotNetDateTimeOffsetTicks') ...
    )*10e-8), ...
    protocolBlocks, ...
    'UniformOutput', 0 ...
    ));
  %sort by start time
  protocolBlocks = protocolBlocks(protocolOrder);
  
  % Find the Protocol parameters common to all epochs of a run protocol
  protocolParamBlocks = arrayfun( ...
    @(a) a.Groups(contains({a.Groups.Name}','/protocolParameters')), ...
    protocolBlocks, ...
    'UniformOutput', 0 ...
    );
  protocolParamBlocks = cat(1,protocolParamBlocks{:});
  
  % Get the epoch blocks: 1 elem in array for each epoch
  numEpochsPerRun = arrayfun( ...
    @(a) length(a.Groups(contains({a.Groups.Name}','/epochs')).Groups), ...
    protocolBlocks, ...
    'UniformOutput', 1 ...
    );
  epochBlocks = arrayfun( ...
    @(a) a.Groups(contains({a.Groups.Name}','/epochs')).Groups, ...
    protocolBlocks, ...
    'UniformOutput', 0 ...
    );
  epochBlocks = cat(1,epochBlocks{:});
  [epochStartTime,epochOrder] = sort(arrayfun( ...
    @(e) sec2str(double( ...
      h5readatt(fileName, e.Name, 'startTimeDotNetDateTimeOffsetTicks') ...
    )*10e-8), ...
    epochBlocks, ...
    'UniformOutput', 0 ...
    ));
  % sort by start time -> this will also help with combining nested props
  epochBlocks = epochBlocks(epochOrder);
  %Epoch Params
  epochParamBlocks = arrayfun( ...
    @(blk)blk.Groups(contains({blk.Groups.Name}','/protocolParameters')), ...
    epochBlocks, ...
    'UniformOutput', 1 ...
    );
  
  % Merge the params
  % Start at protocol Level
  numProtocolsRun = length(numEpochsPerRun);
  tmpArray = arrayfun( ...
    @(v,ofst)(1:v)+ofst, ...
    numEpochsPerRun, ...
    cumsum([0;numEpochsPerRun(1:end-1)]), ...
    'UniformOutput', 0 ...
    );
  propsInCells = cell(numProtocolsRun,1);
  for proto = 1:numProtocolsRun
    fields = [ ...
      {'protocolStartTime'}; ...
      {'protocolID'}; ...
      {protocolParamBlocks(proto).Attributes.Name}' ...
      ];
    values = [ ...
      protocolStartTime(proto); ...
      h5readatt(fileName, protocolBlocks(proto).Name,'protocolID'); ...
      {protocolParamBlocks(proto).Attributes.Value}' ...
      ];
    tmpInds = tmpArray{proto};
    tmpCell = cell(length(tmpInds),1);
    for ep = tmpInds
      tmpCell{ep-tmpInds(1)+1} = ...
        [ ...
          [ ...
            fields; ...
            {'epochStartTime'}; ...
            {epochParamBlocks(ep).Attributes.Name}' ...
          ], ...
          [ ...
            values; ...
            epochStartTime(ep); ...
            {epochParamBlocks(ep).Attributes.Value}' ...
          ] ...
        ];
    end
    propsInCells{proto} = tmpCell;
  end
  % Convert to epoch length
  propsInCells = cat(1, propsInCells{:});
  %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
  nEpochs = length(propsInCells);
  Data(nEpochs,1) = struct( ...
    'protocols', {{}}, ...
    'displayProperties', {{}}, ...
    'id', '', ...
    'responses', struct() ...
    );
    
  % Collect Data
  epochResponses = arrayfun( ...
    @(blk)blk.Groups(contains({blk.Groups.Name}','/responses')).Groups, ...
    epochBlocks, ...
    'UniformOutput', 0 ...
    );
  
  % unused for now
  epochBackgrounds = arrayfun( ...
    @(blk)blk.Groups(contains({blk.Groups.Name}','/backgrounds')), ...
    epochBlocks, ...
    'UniformOutput', 0 ...
    );
  
  epochStimuli = arrayfun( ...
    @(blk)blk.Groups(contains({blk.Groups.Name}','/stimuli')), ...
    epochBlocks, ...
    'UniformOutput', 0 ...
    );
  
  numEpochsInRunRep = rep(numEpochsPerRun,1,numEpochsPerRun);
  curEpochInRun = arrayfun( ...
    @(v)(1:v), ...
    numEpochsPerRun, ...
    'UniformOutput', 0 ...
    );
  curEpochInRun = cat(2,curEpochInRun{:});
  for rGroup = 1:nEpochs
    responseStruct = epochResponses{rGroup};
    nResponses = length(responseStruct);
    responseData = struct( ...
      'sampleRate', {{}}, ...
      'duration', {{}}, ...
      'units', {{}}, ...
      'device', {{}}, ...
      'x', {{}}, ...
      'y', {{}} ...
      );
    for r = 1:nResponses
      responseMap = responseStruct(r);
      rlink = responseMap.Links( ...
        contains({responseMap.Links.Name}','device') ...
        ).Value{:};
      responseData.devices{r} = h5readatt(fileName, rlink,'name');
      d = h5read(fileName,[responseMap.Name,'/data']);
      responseData.y{r} = d.quantity;
      responseData.units(r) = unique(cellstr(d.units'));
      fs = double(h5readatt(fileName, ...
        responseMap.Name, ...
        'sampleRate' ...
        ));
      responseData.sampleRate{r} = fs;
      dur = double(h5readatt(fileName, ...
          [responseMap.Name,'/dataConfigurationSpans/span_0'], ...
          'timeSpanSeconds' ...
        ));
      responseData.duration{r} = dur;
      startTimeSec = h5readatt(fileName, ...
          [responseMap.Name,'/dataConfigurationSpans/span_0'], ...
          'startTimeSeconds' ...
        );
      responseData.x{r} = linspace(...
        startTimeSec, ...
        startTimeSec+dur-1/fs, ...
        dur * fs ...
        )';
    end
    % Get configuration for each stimulus data
    nConfigs = length(epochStimuli{rGroup}.Groups);
    responseData.responseConfiguration = struct( ...
      'deviceName', '', ...
      'configSettings', struct('name', '', 'value', {{}}) ...
      );
    for cfg = 1:nConfigs
      responseData.responseConfiguration(cfg).deviceName = ...
        h5readatt(fileName, ...
          epochStimuli{rGroup}.Groups(cfg).Links( ...
            ismember({epochStimuli{rGroup}.Groups(cfg).Links.Name}','device') ...
          ).Value{1}, ...
          'name' ...
          );
      configLoc = h5info(fileName,...
        [epochStimuli{rGroup}.Groups(cfg).Groups( ...
        contains( ...
          {epochStimuli{rGroup}.Groups(cfg).Groups.Name}', ...
          '/dataConfigurationSpans' ...
          ) ...
        ).Name,'/span_0/',responseData.responseConfiguration(cfg).deviceName ...
        ]);
      for cset = 1:length(configLoc.Attributes)
        responseData.responseConfiguration(cfg).configSettings(cset) = ...
          struct( ...
            'name', configLoc.Attributes(cset).Name, ...
            'value', configLoc.Attributes(cset).Value ...
            );
      end
    end
    % Get configuuration for output devices
    nBackgrounds = length(epochBackgrounds{rGroup}.Groups);
    responseData.devicesConfiguration = struct( ...
      'deviceName', '', ...
      'configSettings', struct('name', '', 'value', {{}}) ...
      );
    for cfg = 1:nBackgrounds
      responseData.deviceConfiguration(cfg).deviceName = ...
        h5readatt(fileName, ...
          epochBackgrounds{rGroup}.Groups(cfg).Links( ...
            ismember({epochBackgrounds{rGroup}.Groups(cfg).Links.Name}','device') ...
          ).Value{1}, ...
          'name' ...
          );
      configLoc = h5info(fileName,...
        [epochBackgrounds{rGroup}.Groups(cfg).Groups( ...
        contains( ...
          {epochBackgrounds{rGroup}.Groups(cfg).Groups.Name}', ...
          '/dataConfigurationSpans' ...
          ) ...
        ).Name,'/span_0/',responseData.deviceConfiguration(cfg).deviceName ...
        ]);
      for cset = 1:length(configLoc.Attributes)
        responseData.deviceConfiguration(cfg).configSettings(cset) = ...
          struct( ...
            'name', configLoc.Attributes(cset).Name, ...
            'value', configLoc.Attributes(cset).Value ...
            );
      end
    end
    
    Data(rGroup,1).responses = responseData;
    Data(rGroup,1).protocols = propsInCells{rGroup};
    % diplsy props
    displayNames = propsInCells{rGroup}( ...
      ismember(propsInCells{rGroup}(:,1), ...
        { ...
        'amplifierHoldingPotential', 'protocolID', 'sampleRate'
        } ...
      ), ...
      1 ...
      );
    displayValues = propsInCells{rGroup}( ...
      ismember(propsInCells{rGroup}(:,1), displayNames), ...
      2 ...
      );
    dateAndTime = strsplit( ...
      propsInCells{rGroup}{ ...
        find(ismember(propsInCells{rGroup}(:,1),'epochDateString'),1,'first'), ...
      2 }, ...
      '_');
    displayName = [ ...
      displayNames(:); ...
      { ...
        'NumEpochsInRun'; 'CurrentEpochInRun'; 'Date'; 'Time' ...
      } ...
      ];
    displayValues = [ ...
      displayValues(:); ...
      { ...
        numEpochsInRunRep(rGroup); curEpochInRun(rGroup); ...
        dateAndTime{1}; dateAndTime{2} ...
      } ...
      ];
    Data(rGroup,1).displayProperties = [displayName(:),displayValues(:)];
  end %end of data collection loop
  
end

end %end of reader

%% Helpers
function S = rmAllfields(S, fname)
  if nargin < 2, fname = {'gitHash', 'version'}; end
  fn = fieldnames(S);
  fKeep = ~ismember(fn, fname);
  fdat = struct2cell(S);
  S = cell2struct(fdat(fKeep), fn(fKeep),1);
end

function S = keepFields(S,keepers)
  fn = fieldnames(S);
  fKeep = ismember(fn,keepers);
  fdat = struct2cell(S);
  S = cell2struct(fdat(fKeep),fn(fKeep),1);
end

function S = insertField(S,fname,val)
  fname = cellstr(fname);
  for f = 1:length(fname)
    S.(fname{f}) = val{f};
  end
end

function [ tString,varargout ] = sec2str( secs, ofst )
  if nargin < 2, ofst = 0; end
  tString = {};
  for tSec = secs(:)'
    h = fix(tSec/60^2);
    hfrac = round(24*(h/24-fix(h/24)),0);
    m = fix((tSec-h*60^2)/60);
    s = fix(tSec-h*60^2-m*60);
    ms = fix((tSec - fix(tSec)) * 10^4);
    tString{end+1,1} = sprintf('%02d:%02d:%02d.%04d',hfrac+ofst,m,s,ms);%#ok<AGROW>
  end
  varargout{1} = tString;
  if length(tString) == 1
    tString = tString{:};
  end
end

function tsec = str2sec(str)%#ok
  spt = strsplit(str,':');
  nums = str2double(flipud(spt(:))); %s,m,h now
  tsec = 0;
  for nn = 1:length(nums)
    tsec = nums(nn)*60^(nn-1) + tsec;
  end
end

function catStrc = repCat(base,add)
  %add = which struct to replicate and fold INTO base (thus base = n>1, add = n==1)
  import *;
  aF = fieldnames(add);
  aV = struct2cell(add);
  if ~numel(base), catStrc = []; end
  for f = 1:numel(base)
    bF = fieldnames(base(f));
    bV = struct2cell(base(f));
    [fNs,b,~] = unique([bF;aF]);
    valtmps = [bV;aV];
    valtmps = valtmps(b);
    combinedValues = arrayfun(...
      @unknownCell2Str, valtmps,'unif',0);

    catStrc(f,1) = cell2struct(...
        combinedValues, ...
        fNs, ...
        1 ...
      );%#ok<AGROW>
  end
end

function base = structCat(base,newField,fieldData)
  for b = 1:numel(base)
    try
      base(b).(newField) = fieldData;
    catch x
      x.message = cat(2,{x.message},sprintf('%s could not be inserted.',newField));
    end
  end
end