classdef CNNTrainingAnnotator < handle
    % CNNTrainingAnnotator
    % Standalone GUI for creating 3-frame pseudo-RGB CNN training images
    % and binary region masks from MP4 video frames.
    %
    % Usage:
    %   app = CNNTrainingAnnotator;
    %
    % Workflow:
    %   1. Browse/select an MP4 file.
    %   2. Choose a center frame. Frames [N-1 N N+1] are stacked as RGB.
    %   3. Click "Add region" and encircle foreground regions.
    %   4. Click "Remove region" to encircle regions that should be removed.
    %   5. Save the annotation. The image, binary mask, and editable log are
    %      written to trainingImage, trainingLabel, and trainingLog.

    properties (Access = public)
        UIFigure                    matlab.ui.Figure
        SourcePanel                 matlab.ui.container.Panel
        BrowseVideoButton           matlab.ui.control.Button
        VideoPathEditField          matlab.ui.control.EditField
        FrameSpinnerLabel           matlab.ui.control.Label
        FrameSpinner                matlab.ui.control.Spinner
        LoadFrameButton             matlab.ui.control.Button
        ArchivePanel                matlab.ui.container.Panel
        BrowseArchiveButton         matlab.ui.control.Button
        ArchivePathEditField        matlab.ui.control.EditField
        AnnotationPanel             matlab.ui.container.Panel
        AddButton                   matlab.ui.control.Button
        RemoveButton                matlab.ui.control.Button
        UndoButton                  matlab.ui.control.Button
        ClearButton                 matlab.ui.control.Button
        SaveButton                  matlab.ui.control.Button
        StatusLabel                 matlab.ui.control.Label
        Axes                        matlab.ui.control.UIAxes
        CameraIDLabel               matlab.ui.control.Label
        CameraIDDropDown            matlab.ui.control.DropDown
        CameraDescriptionLabel      matlab.ui.control.Label
    end

    properties (Access = private)
        VideoReaderObj
        VideoFile char = ''
        % for rectification
        RectificationReady logical = false
        CameraID char = 'rod13'
        info
        icp
        beta0
        descriptionStr char = ''
        % Raw image coordinate grid
        U
        V
        % Rectified/world coordinate grid
        X
        Y
        % Mapping from rectified world grid -> raw image coordinates
        Uint
        Vint
        % for pseudo-RGB frames
        CenterFrame double = 2
        CurrentFrames double = []
        CurrentImage uint8 = []
        CurrentMask uint8 = []
        BaseMask uint8 = []
        RegionHistory = struct('id', {}, 'action', {}, 'vertices', {}, 'frameNumbers', {}, ...
            'timestamp', {}, 'maskPixelCount', {})
        ActiveROIs = gobjects(0)
        ArchiveRoot char = ''
        IsLoaded logical = false
    end

    methods (Access = public)
        function app = CNNTrainingAnnotator()
            createComponents(app);
            restorePreferences(app);
            cameraIDChanged(app);
            updateUIState(app);
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure);
            end
        end
    end

    methods (Access = private)

        function createComponents(app)
            % =========================================================
            % Main figure
            % =========================================================
            app.UIFigure = uifigure( ...
                'Name','CNN Training Annotator', ...
                'Position',[100 100 1350 850], ...
                'Color',[0.94 0.94 0.94]);
            % =========================================================
            % Input video / camera panel
            % =========================================================
            app.SourcePanel = uipanel( ...
                app.UIFigure, ...
                'Title','Input video / camera', ...
                'Position',[15 745 1320 90]);
            % ---------------------------------------------------------
            % Row 1: video
            % ---------------------------------------------------------
            
            app.BrowseVideoButton = uibutton( ...
                app.SourcePanel, ...
                'push', ...
                'Text','Browse MP4...', ...
                'Position',[10 48 100 28], ...
                'ButtonPushedFcn', ...
                @(src,event)browseVideo(app));
            
            app.VideoPathEditField = uieditfield( ...
                app.SourcePanel, ...
                'text', ...
                'Position',[120 48 760 28], ...
                'Editable','off');
            
            app.FrameSpinnerLabel = uilabel( ...
                app.SourcePanel, ...
                'Text','Center frame:', ...
                'Position',[900 52 82 22]);
            
            app.FrameSpinner = uispinner( ...
                app.SourcePanel, ...
                'Position',[982 48 100 28], ...
                'Limits',[2 Inf], ...
                'RoundFractionalValues','on', ...
                'ValueChangedFcn', ...
                @(src,event)frameChanged(app));
            
            app.LoadFrameButton = uibutton( ...
                app.SourcePanel, ...
                'push', ...
                'Text','Load frame', ...
                'Position',[1095 48 95 28], ...
                'ButtonPushedFcn', ...
                @(src,event)loadSelectedFrames(app));
            
            % ---------------------------------------------------------
            % Row 2: camera ID
            % ---------------------------------------------------------
            app.CameraIDLabel = uilabel( ...
                app.SourcePanel, ...
                'Text','Camera ID:', ...
                'Position',[10 12 75 22]);
            
            app.CameraIDDropDown = uidropdown( ...
                app.SourcePanel, ...
                'Items',{'top21','bot21','top22','bot22','top18','bot18','rod13'}, ...
                'Value','rod13', ...
                'Position',[90 10 120 25], ...
                'ValueChangedFcn', ...
                @(src,event)cameraIDChanged(app));

            % Informational label
            app.CameraDescriptionLabel = uilabel( ...
                app.SourcePanel, ...
                'Text','Camera not initialized', ...
                'Position',[230 10 950 25]);

            % =========================================================
            % Training archive panel
            % =========================================================

            app.ArchivePanel = uipanel( ...
                app.UIFigure, ...
                'Title','Training archive', ...
                'Position',[15 680 1320 55]);

            app.BrowseArchiveButton = uibutton( ...
                app.ArchivePanel, ...
                'push', ...
                'Text','Browse...', ...
                'Position',[10 10 80 28], ...
                'ButtonPushedFcn', ...
                @(src,event)browseArchive(app));

            app.ArchivePathEditField = uieditfield( ...
                app.ArchivePanel, ...
                'text', ...
                'Position',[100 10 1080 28], ...
                'Editable','off');

            % =========================================================
            % Annotation panel
            % =========================================================
            app.AnnotationPanel = uipanel( ...
                app.UIFigure, ...
                'Title','Annotation tools', ...
                'Position',[15 615 1320 55]);

            app.AddButton = uibutton( ...
                app.AnnotationPanel, ...
                'push', ...
                'Text','Add region', ...
                'Position',[10 10 100 28], ...
                'ButtonPushedFcn', ...
                @(src,event)addRegion(app));

            app.RemoveButton = uibutton( ...
                app.AnnotationPanel, ...
                'push', ...
                'Text','Remove region', ...
                'Position',[120 10 110 28], ...
                'ButtonPushedFcn', ...
                @(src,event)removeRegion(app));

            app.UndoButton = uibutton( ...
                app.AnnotationPanel, ...
                'push', ...
                'Text','Undo last', ...
                'Position',[240 10 100 28], ...
                'ButtonPushedFcn', ...
                @(src,event)undoLast(app));

            app.ClearButton = uibutton( ...
                app.AnnotationPanel, ...
                'push', ...
                'Text','Clear mask', ...
                'Position',[350 10 100 28], ...
                'ButtonPushedFcn', ...
                @(src,event)clearMask(app));

            app.SaveButton = uibutton( ...
                app.AnnotationPanel, ...
                'push', ...
                'Text','Save annotation', ...
                'Position',[460 10 120 28], ...
                'ButtonPushedFcn', ...
                @(src,event)saveAnnotation(app));

            app.StatusLabel = uilabel( ...
                app.AnnotationPanel, ...
                'Text','No video loaded.', ...
                'Position',[600 10 680 28]);

            % =========================================================
            % Main image axes
            % =========================================================
            app.Axes = uiaxes( ...
                app.UIFigure, ...
                'Position',[45 45 1270 555]);

            app.Axes.XTick = [];
            app.Axes.YTick = [];
            app.Axes.Toolbar.Visible = 'on';

            title(app.Axes,'Select a video and load a frame');
        end

        function restorePreferences(app)
            prefsFile = fullfile(prefdir,'CNNTrainingAnnotator.mat');
            if exist(prefsFile,'file')
                try
                    S = load(prefsFile,'ArchiveRoot','VideoFile');
                    if isfield(S,'ArchiveRoot') && isfolder(S.ArchiveRoot)
                        app.ArchiveRoot = S.ArchiveRoot;
                        app.ArchivePathEditField.Value = S.ArchiveRoot;
                    end
                    if isfield(S,'VideoFile') && isfile(S.VideoFile)
                        app.VideoFile = S.VideoFile;
                        app.VideoPathEditField.Value = S.VideoFile;
                        openVideo(app);
                    end
                catch
                end
            end
        end

        function savePreferences(app)
            prefsFile = fullfile(prefdir,'CNNTrainingAnnotator.mat');
            ArchiveRoot = app.ArchiveRoot;
            VideoFile = app.VideoFile;
            try
                save(prefsFile,'ArchiveRoot','VideoFile');
            catch
            end
        end

        function cameraIDChanged(app)
            app.CameraID = app.CameraIDDropDown.Value;
            try
                % -----------------------------------------------------
                % Load camera/grid parameters
                % -----------------------------------------------------                
                [app.info, app.icp, app.beta0, app.descriptionStr] = ...
                                 define_camera_parameters_new(app.CameraID);
                % -----------------------------------------------------
                % Raw image pixel coordinates
                % -----------------------------------------------------
                [app.U, app.V] = meshgrid(0:app.icp.NU-1, 0:app.icp.NV-1);
                % -----------------------------------------------------
                % Rectified/world coordinates
                % -----------------------------------------------------
                app.X = app.info.X_min:app.info.X_res:app.info.X_max;
                app.Y = app.info.Y_min:app.info.Y_res:app.info.Y_max;
                % -----------------------------------------------------
                % Map every world-grid point to raw image coordinates
                % -----------------------------------------------------
                [xx,yy] = meshgrid(app.X,app.Y);
                z_tide  = zeros(size(xx));
                [app.Uint,app.Vint] = ...
                    getUVfromXYZ(xx,yy,z_tide,app.icp,app.beta0);
                % ready to rectify image
                app.RectificationReady = true;
                %
                setStatus(app,sprintf( ...
                    'Camera %s initialized: %s', ...
                    app.CameraID, ...
                    app.descriptionStr));
                app.CameraDescriptionLabel.Text = 'Camera parameters initialized';
            catch ME
                app.RectificationReady = false;
                uialert(app.UIFigure, ...
                        ME.message, ...
                        sprintf('Could not initialize camera %s',app.CameraID));
            end
            updateUIState(app);
        end

        function browseVideo(app)
            app.UIFigure.Visible = 'off'; % Hide the main window
            [file,path] = uigetfile({'*.*','All files'}, ...
                                    'Select source video', ...
                                     getInitialFolder(app,'video'));
            app.UIFigure.Visible = 'on'; % show the main window
            if isequal(file,0); return; end
            app.VideoFile = fullfile(path,file);
            app.VideoPathEditField.Value = app.VideoFile;
            openVideo(app);
            savePreferences(app);
        end

        function browseArchive(app)
            if isempty(app.ArchiveRoot) || ~isfolder(app.ArchiveRoot)
                startDir = pwd;
            else
                startDir = app.ArchiveRoot;
            end
            d = uigetdir(startDir,'Select training archive directory');
            if isequal(d,0); return; end
            app.ArchiveRoot = d;
            app.ArchivePathEditField.Value = d;
            savePreferences(app);
            setStatus(app,'Archive directory selected.');
            updateUIState(app);
        end

        function openVideo(app)
            try
                app.VideoReaderObj = VideoReader(app.VideoFile);
                nFrames = floor(app.VideoReaderObj.Duration * app.VideoReaderObj.FrameRate);
                app.CenterFrame = max(2,min(nFrames-1,app.CenterFrame));
                app.FrameSpinner.Limits = [2 max(2,nFrames-1)];
                app.FrameSpinner.Value = app.CenterFrame;
                app.IsLoaded = false;
                setStatus(app,sprintf('Loaded %s (%d frames at %.3f Hz).', ...
                    app.VideoFile,nFrames,app.VideoReaderObj.FrameRate));
            catch ME
                app.VideoReaderObj = [];
                app.IsLoaded = false;
                uialert(app.UIFigure,ME.message,'Could not open video');
            end
            updateUIState(app);
        end

        function frameChanged(app)
            if isempty(app.VideoReaderObj); return; end
            app.CenterFrame = round(app.FrameSpinner.Value);
        end

        function loadSelectedFrames(app)
            % check for video
            if isempty(app.VideoReaderObj)
                uialert(app.UIFigure, ...
                        'Select a video first.', ...
                        'No video');
                return
            end
            % check for camera parameters/rectification
            if ~app.RectificationReady
                cameraIDChanged(app);
                if ~app.RectificationReady
                    return
                end
            end
            
            % Center frame
            c = round(app.FrameSpinner.Value);
            % Three-frame stack
            idx = [c-1 c c+1];

            try
                % -----------------------------------------------------
                % Allocate rectified pseudo-RGB image
                % -----------------------------------------------------
                Ny = numel(app.Y);
                Nx = numel(app.X);
                IMG = zeros(Ny,Nx,3,'uint8');
                % -----------------------------------------------------
                % Read and rectify each frame
                % -----------------------------------------------------
                for ii = 1:3
                    frameNumber = idx(ii);
                    app.VideoReaderObj.CurrentTime = ...
                        (frameNumber-1) / app.VideoReaderObj.FrameRate;
                    frame = read(app.VideoReaderObj,frameNumber);

                    % Convert RGB -> grayscale
                    if size(frame,3) == 3
                        IMGraw = rgb2gray(frame);
                    else
                        IMGraw = frame;
                    end
                    
                    IMGraw = double(IMGraw);
                    
                    % Rectify onto X-Y grid
                    IMGrect = interp2(app.U,app.V,IMGraw,app.Uint,app.Vint,...
                                      'linear',NaN);

                    % Convert to uint8 while preserving NaNs as zero
                    valid      = isfinite(IMGrect);
                    tmp        = zeros(size(IMGrect));
                    tmp(valid) = IMGrect(valid);
                    tmp = max(0,min(255,tmp));

                    IMG(:,:,ii) = uint8(tmp);
        end

        % Store
        app.CurrentFrames = idx;
        app.CurrentImage = IMG;
        % ---------------------------------------------------------
        % Initialize three-class training mask
        %   0   = Background
        %   127 = Water / Land
        %   255 = User-selected wave
        % ---------------------------------------------------------
        app.BaseMask = zeros(size(app.CurrentImage,1), ...
                             size(app.CurrentImage,2), ...
                             'uint8');
        
        isBlack = all(app.CurrentImage < 15, 3);
        app.BaseMask(isBlack) = uint8(0);
        
        isGray = ~isBlack;
        app.BaseMask(isGray) = uint8(127);

        % Start current mask from the base classification
        app.CurrentMask = app.BaseMask;

        % Reset annotations for new frame stack
        app.RegionHistory = struct( ...
            'id', {}, ...
            'action', {}, ...
            'vertices', {}, ...
            'frameNumbers', {}, ...
            'timestamp', {}, ...
            'maskPixelCount', {});

        clearROIObjects(app);
        app.IsLoaded = true;
        showCurrentImage(app);
        setStatus(app,sprintf( ...
            'Camera %s: rectified frames %d, %d, %d.', ...
            app.CameraID, ...
            idx(1),idx(2),idx(3)));
    catch ME
        uialert(app.UIFigure, ...
            ME.message, ...
            'Could not load/rectify frames');
    end

    updateUIState(app);

end        

        function showCurrentImage(app)
            if isempty(app.CurrentImage); return; end
            imagesc(app.Axes,app.X,app.Y,app.CurrentImage);
            axis(app.Axes,'image');
% $$$             app.Axes.XTick = [];
% $$$             app.Axes.YTick = [];
            set(app.Axes,'ydir','normal','tickdir','out')
            title(app.Axes,sprintf('Frames %d : %d : %d | Add/remove regions', ...
                app.CurrentFrames));
            app.Axes.Toolbar.Visible = 'on';
            drawMaskOverlay(app);
        end

        function drawMaskOverlay(app)
            % Remove previous overlay if any
            old = findobj(app.Axes,'Tag','MaskOverlay');
            if ~isempty(old); delete(old); end
            if isempty(app.CurrentMask); return; end
            % make RGB overlay:
            maskRGB = repmat(app.CurrentMask,[1 1 3]);
            hold(app.Axes,'on');
            h = imagesc(app.Axes,app.X,app.Y,maskRGB);
            h.Tag = 'MaskOverlay';
            h.AlphaData = 0.35 * double(app.CurrentMask==255);
            hold(app.Axes,'off');
            uistack(h,'top');
            axis(app.Axes,'image')
        end

        function addRegion(app)
            drawRegion(app,'add');
        end

        function removeRegion(app)
            drawRegion(app,'remove');
        end

        function drawRegion(app,action)
            if ~app.IsLoaded
                uialert(app.UIFigure,'Load a frame stack first.','No image');
                return;
            end
            if strcmp(action,'add')
                prompt = 'Encircle a foreground region, double-click to finish.';
            else
                prompt = 'Encircle a region to remove from the mask, double-click to finish.';
            end
            setStatus(app,prompt);
            roi = drawfreehand(app.Axes,'Color',chooseColor(action), ...
                'Closed',true,'FaceAlpha',0.12);
            try
                wait(roi);
            catch
            end
            if ~isvalid(roi) | isempty(roi.Position); return; end
            verts = roi.Position;
            % ROI is physical coordinates, but mask uses pixel coords...
            [xpix,ypix] = worldToPixel(app,verts);
            %            regionMask = createMask(roi);
            regionMask  = poly2mask(xpix,ypix,...
                                   size(app.CurrentMask,1),size(app.CurrentMask,2));
            if strcmp(action,'add')
                % update mask with classification                
                app.CurrentMask(regionMask) = uint8(255);
            else
                % Restore underlying background/water classification
                app.CurrentMask(regionMask) = app.BaseMask(regionMask);
            end
            entry.id = numel(app.RegionHistory) + 1;
            entry.action = action;
            entry.vertices = verts;
            entry.frameNumbers = app.CurrentFrames;
            entry.timestamp = datetime('now');
            entry.maskPixelCount = nnz(app.CurrentMask);
            app.RegionHistory(end+1) = entry;
            app.ActiveROIs(end+1) = roi;
            drawMaskOverlay(app);
            setStatus(app,sprintf('%s region added. Current foreground pixels: %d.', ...
                                  capitalize(action),nnz(app.CurrentMask)));
            updateUIState(app);
        end

        function [xpix,ypix] = worldToPixel(app,xy)
            xpix = 1 + (xy(:,1) - app.X(1)) / app.info.X_res;
            ypix = 1 + (xy(:,2) - app.Y(1)) / app.info.Y_res;
        end
        
        function undoLast(app)
            if isempty(app.RegionHistory)
                setStatus(app,'Nothing to undo.');
                return;
            end
            app.RegionHistory(end) = [];
            clearROIObjects(app);
            app.CurrentMask = app.BaseMask;
            history = app.RegionHistory;
            for k = 1:numel(history)
                [xpix,ypix] = worldToPixel(app,history(k).vertices);
                poly        = poly2mask(xpix,ypix, ...
                                 size(app.CurrentMask,1),size(app.CurrentMask,2));
                if strcmp(history(k).action,'add')
                    app.CurrentMask(poly) = uint8(255);
                else strcmp(history(k).action,'remove')
                    app.CurrentMask(poly) = app.BaseMask(poly);
                end
            end
            redrawHistoryROIs(app);
            drawMaskOverlay(app);
            setStatus(app,sprintf('Undid last region. Current foreground pixels: %d.',nnz(app.CurrentMask)));
        end

        function clearMask(app)
            if ~app.IsLoaded; return; end
            choice = uiconfirm(app.UIFigure,'Clear all annotations for this frame stack?', ...
                'Clear mask','Options',{'Clear','Cancel'},'DefaultOption',2);
            if ~strcmp(choice,'Clear'); return; end
            app.CurrentMask = false(size(app.CurrentMask));
            app.RegionHistory = struct('id', {}, 'action', {}, 'vertices', {}, ...
                'frameNumbers', {}, 'timestamp', {}, 'maskPixelCount', {});
            clearROIObjects(app);
            drawMaskOverlay(app);
            setStatus(app,'Mask cleared.');
        end

        function redrawHistoryROIs(app)
            clearROIObjects(app);
            for k = 1:numel(app.RegionHistory)
                c = chooseColor(app.RegionHistory(k).action);
                roi = drawfreehand(app.Axes,'Position',app.RegionHistory(k).vertices, ...
                    'Color',c,'FaceAlpha',0.05,'InteractionsAllowed','none');
                app.ActiveROIs(end+1) = roi;
            end
        end

        function clearROIObjects(app)
            if isempty(app.ActiveROIs); return; end
            valid = isgraphics(app.ActiveROIs);
            delete(app.ActiveROIs(valid));
            app.ActiveROIs = gobjects(0);
        end

        function saveAnnotation(app)
            if ~app.IsLoaded
                uialert(app.UIFigure,'Load and annotate a frame stack first.','Nothing to save');
                return;
            end
            if isempty(app.ArchiveRoot) || ~isfolder(app.ArchiveRoot)
                d = uigetdir(pwd,'Select training archive directory');
                if isequal(d,0); return; end
                app.ArchiveRoot = d;
                app.ArchivePathEditField.Value = d;
                savePreferences(app);
            end
            imgDir = fullfile(app.ArchiveRoot,'trainingImage');
            lblDir = fullfile(app.ArchiveRoot,'trainingLabel');
            logDir = fullfile(app.ArchiveRoot,'trainingLog');
            if ~exist(imgDir,'dir'); mkdir(imgDir); end
            if ~exist(lblDir,'dir'); mkdir(lblDir); end
            if ~exist(logDir,'dir'); mkdir(logDir); end

            [~,srcBase,~] = fileparts(app.VideoFile);
            stem = sprintf('%s_%s_f%06d',sanitizeName(srcBase),app.CameraID,app.CenterFrame);
            imgFile = fullfile(imgDir,[stem '.png']);
            lblFile = fullfile(lblDir,[stem '.png']);
            logFile = fullfile(logDir,[stem '.mat']);

            % Write pseudo-RGB image and binary mask. Label is uint8 0/1.
            imwrite(app.CurrentImage,imgFile,'png');
            imwrite(uint8(app.CurrentMask),lblFile,'png');

            log.sourceVideo = app.VideoFile;
            log.sourceVideoRelativePath = app.VideoFile;
            log.cameraID          = app.CameraID;
            log.cameraDescription = app.descriptionStr;
            log.X = app.X;
            log.Y = app.Y;
            log.X_res = app.info.X_res;
            log.Y_res = app.info.Y_res;
            log.frameRate = app.VideoReaderObj.FrameRate;
            log.frameNumbers = app.CurrentFrames;
            log.centerFrame = app.CenterFrame;
            log.imageFilename = imgFile;
            log.labelFilename = lblFile;
            log.imageSize = size(app.CurrentImage);
            log.maskSize = size(app.CurrentMask);
            log.regionHistory = app.RegionHistory;
            log.maskPixelIndex = find(app.CurrentMask);
            log.maskPixelCount = nnz(app.CurrentMask==255);
            log.created = datetime('now');
            log.archiveRoot = app.ArchiveRoot;
            save(logFile,'-struct','log','-v7');

            % Export a compact human-readable companion log.
            txtFile = fullfile(logDir,[stem '.txt']);
            fid = fopen(txtFile,'w');
            if fid >= 0
                c = onCleanup(@() fclose(fid));
                fprintf(fid,'CNN Training Annotation Log\n');
                fprintf(fid,'Created: %s\n',char(log.created));
                fprintf(fid,'Source video: %s\n',log.sourceVideo);
                fprintf(fid,'Frame numbers: %s\n',mat2str(log.frameNumbers));
                fprintf(fid,'Pseudo-RGB image: %s\n',imgFile);
                fprintf(fid,'Binary label: %s\n',lblFile);
                fprintf(fid,'Foreground pixels: %d\n',log.maskPixelCount);
                fprintf(fid,'Regions: %d\n',numel(log.regionHistory));
                for k = 1:numel(log.regionHistory)
                    fprintf(fid,'  Region %d: %s, %d vertices, mask pixels after op=%d\n', ...
                        k,log.regionHistory(k).action,size(log.regionHistory(k).vertices,1), ...
                        log.regionHistory(k).maskPixelCount);
                end
            end

            setStatus(app,sprintf('Saved %s and mask/log to %s.',stem,app.ArchiveRoot));
        end

        function updateUIState(app)
            loaded = app.IsLoaded && ~isempty(app.CurrentImage);
            app.AddButton.Enable = onoff(loaded);
            app.RemoveButton.Enable = onoff(loaded);
            app.UndoButton.Enable = onoff(loaded && ~isempty(app.RegionHistory));
            app.ClearButton.Enable = onoff(loaded && any(app.CurrentMask(:)));
            app.SaveButton.Enable = onoff(loaded);
            app.LoadFrameButton.Enable = onoff(~isempty(app.VideoReaderObj));
        end

        function setStatus(app,msg)
            if isvalid(app.StatusLabel)
                app.StatusLabel.Text = msg;
                drawnow limitrate;
            end
        end

        function folder = getInitialFolder(app,kind)
            switch kind
                case 'video'
                    if ~isempty(app.VideoFile) && isfile(app.VideoFile)
                        folder = fileparts(app.VideoFile);
                    else
                        folder = pwd;
                    end
                otherwise
                    folder = pwd;
            end
        end
    end
end

function c = chooseColor(action)
if strcmp(action,'add')
    c = [0.1 0.9 0.2];
else
    c = [1.0 0.2 0.1];
end
end

function s = capitalize(s)
s(1) = upper(s(1));
end

function val = onoff(tf)
if tf; val = 'on'; else; val = 'off'; end
end

function s = sanitizeName(s)
s = regexprep(s,'[^A-Za-z0-9_.-]','_');
end
