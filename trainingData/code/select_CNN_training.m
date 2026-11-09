classdef select_CNN_training < matlab.apps.AppBase
%SELECT_CNN_TRAINING Wacom-friendly annotation app for waveIMG CNN training.
%
% This app is designed for 3-frame rectified video stacks used as CNN/UNet
% training input.  The three frames are stored as RGB channels in IMG and a
% corresponding uint8 class mask is archived with:
%
%   0   = background / outside image
%   127 = water
%   255 = breaking wave / foam
%
% The default preprocessing follows MAIN_FLOW_RECENT.m:
%   * define_camera_parameters_new(ID)
%   * build the X/Y rectified grid
%   * rectify three consecutive sampled video frames
%   * optionally apply the same contrast enhancement used there
%
% The app does NOT write to GitHub.  All annotation products are written to
% the selected local training-data directory.

    properties (Access = public)
        UIFigure matlab.ui.Figure
        UIAxes matlab.ui.control.UIAxes
        RootDirectoryEditField matlab.ui.control.EditField
        RootDirectoryEditFieldLabel matlab.ui.control.Label
        BrowseRootButton matlab.ui.control.Button
        VideoDirectoryEditField matlab.ui.control.EditField
        VideoDirectoryEditFieldLabel matlab.ui.control.Label
        BrowseVideoButton matlab.ui.control.Button
        CameraIDEditField matlab.ui.control.EditField
        CameraIDEditFieldLabel matlab.ui.control.Label
        LoadVideoButton matlab.ui.control.Button
        VideoFileDropDown matlab.ui.control.DropDown
        VideoFileDropDownLabel matlab.ui.control.Label
        FrameEditField matlab.ui.control.NumericEditField
        FrameEditFieldLabel matlab.ui.control.Label
        PreviousButton matlab.ui.control.Button
        NextButton matlab.ui.control.Button
        DisplayDropDown matlab.ui.control.DropDown
        DisplayDropDownLabel matlab.ui.control.Label
        EnhanceCheckBox matlab.ui.control.CheckBox
        BackgroundButton matlab.ui.control.Button
        WaterButton matlab.ui.control.Button
        BreakingButton matlab.ui.control.Button
        EraseButton matlab.ui.control.Button
        UndoButton matlab.ui.control.Button
        ClearButton matlab.ui.control.Button
        SaveButton matlab.ui.control.Button
        StatusTextArea matlab.ui.control.TextArea
        BrushSizeEditField matlab.ui.control.NumericEditField
        BrushSizeEditFieldLabel matlab.ui.control.Label
        OverlayCheckBox matlab.ui.control.CheckBox
    end

    properties (Access = private)
        rootDir = ''
        videoDir = ''
        cameraID = ''
        info = []
        icp = []
        beta0 = []
        vid = []
        videoFiles = struct([])
        X = []
        Y = []
        U = []
        V = []
        Uint = []
        Vint = []
        videoFrameIndices = []
        IMG = []
        LBL = []
        currentFrameIndex = 1              % index into sampled 3-frame stacks
        selectedVideoFile = ''
        selectedClass = uint8(255)
        undoStack = {}
        displayDirty = true
        enhanceImage = false
        archiveRoot = ''
        currentImageName = ''
        currentLabelName = ''
        currentMetaName = ''
    end

    methods (Access = private)

        function setStatus(app, msg)
            if ischar(msg) || isstring(msg)
                app.StatusTextArea.Value = splitlines(string(msg));
            else
                app.StatusTextArea.Value = {char(msg)};
            end
            drawnow limitrate
        end

        function updateFileList(app)
            if isempty(app.VideoDirectoryEditField.Value) || ~isfolder(app.VideoDirectoryEditField.Value)
                app.VideoFileDropDown.Items = {'<select video directory>'};
                app.VideoFileDropDown.ItemsData = {''};
                return
            end
            d = [dir(fullfile(app.VideoDirectoryEditField.Value,'*.mp4')); ...
                 dir(fullfile(app.VideoDirectoryEditField.Value,'*.avi')); ...
                 dir(fullfile(app.VideoDirectoryEditField.Value,'*.MP4')); ...
                 dir(fullfile(app.VideoDirectoryEditField.Value,'*.AVI'))];
            if isempty(d)
                app.VideoFileDropDown.Items = {'<no video files found>'};
                app.VideoFileDropDown.ItemsData = {''};
                return
            end
            [~,ii] = sort({d.name});
            d = d(ii);
            app.videoFiles = d;
            names = {d.name};
            app.VideoFileDropDown.Items = names;
            app.VideoFileDropDown.ItemsData = names;
            app.VideoFileDropDown.Value = names{1};
        end

        function setupRoot(app)
            d = uigetdir(pwd,'Select local waveIMG root directory');
            if isequal(d,0); return; end
            app.rootDir = d;
            app.RootDirectoryEditField.Value = d;
            addpath(genpath(d));
            if isfolder(fullfile(d,'trainingData'))
                app.archiveRoot = fullfile(d,'trainingData');
            else
                app.archiveRoot = fullfile(d,'trainingData');
                mkdir(app.archiveRoot);
            end
            mkdir(fullfile(app.archiveRoot,'trainingImages'));
            mkdir(fullfile(app.archiveRoot,'trainingLabels'));
            mkdir(fullfile(app.archiveRoot,'trainingMeta'));
            app.setStatus(sprintf('waveIMG root set to:\n%s',d));
        end

        function setupVideoDir(app)
            d = uigetdir(app.rootDir,'Select directory containing the new video files');
            if isequal(d,0); return; end
            app.videoDir = d;
            app.VideoDirectoryEditField.Value = d;
            app.updateFileList();
        end

        function loadVideo(app)
            app.rootDir = char(app.RootDirectoryEditField.Value);
            app.videoDir = char(app.VideoDirectoryEditField.Value);
            app.cameraID = char(app.CameraIDEditField.Value);
            if isempty(app.rootDir) || ~isfolder(app.rootDir)
                error('Set the waveIMG root directory first.');
            end
            addpath(genpath(app.rootDir));
            if isempty(app.cameraID)
                error('Enter the camera ID used by define_camera_parameters_new (for example top21, bot21, or rod13).');
            end
            vf = char(app.VideoFileDropDown.Value);
            if isempty(vf) || startsWith(vf,'<')
                error('Select a video file.');
            end

            [app.info, app.icp, app.beta0] = define_camera_parameters_new(app.cameraID);
            app.vid = VideoReader(fullfile(app.videoDir,vf));
            app.selectedVideoFile = fullfile(app.videoDir,vf);

            samp = max(1,round(app.vid.FrameRate/app.info.freq));
            % Need a 3-frame centered stack for every annotation state.
            app.videoFrameIndices = 1:samp:app.vid.NumFrames;
            if numel(app.videoFrameIndices) < 3
                error('Video does not contain enough sampled frames for a 3-frame stack.');
            end
            app.currentFrameIndex = 1;

            [app.U,app.V] = meshgrid(0:app.icp.NU-1,0:app.icp.NV-1);
            app.X = app.info.X_min:app.info.X_res:app.info.X_max;
            app.Y = app.info.Y_min:app.info.Y_res:app.info.Y_max;
            [xx,yy] = meshgrid(app.X,app.Y);
            z_tide = zeros(size(xx));
            [app.Uint,app.Vint] = getUVfromXYZ(xx,yy,z_tide,app.icp,app.beta0);

            app.archiveRoot = fullfile(app.rootDir,'trainingData');
            mkdir(app.archiveRoot);
            mkdir(fullfile(app.archiveRoot,'trainingImages'));
            mkdir(fullfile(app.archiveRoot,'trainingLabels'));
            mkdir(fullfile(app.archiveRoot,'trainingMeta'));

            app.loadStack();
            app.setStatus(sprintf('Loaded %s\nFrames sampled every %d video frame(s); %d usable 3-frame stacks.', ...
                vf,samp,max(0,numel(app.videoFrameIndices)-2)));
        end

        function loadStack(app)
            if isempty(app.vid); return; end
            if app.currentFrameIndex > numel(app.videoFrameIndices)-2
                app.currentFrameIndex = max(1,numel(app.videoFrameIndices)-2);
            end
            frames = app.videoFrameIndices(app.currentFrameIndex:app.currentFrameIndex+2);
            IMG = zeros([numel(app.Y),numel(app.X),3],'uint8');
            for ii = 1:3
                raw = read(app.vid,frames(ii));
                if size(raw,3) == 3
                    raw = rgb2gray(raw);
                end
                raw = double(raw);
                rect = interp2(app.U,app.V,raw,app.Uint,app.Vint,'linear',nan);
                if app.enhanceImage
                    vals = rect(isfinite(rect));
                    if isempty(vals)
                        foam_th = 0;
                    else
                        foam_th = app.estimateFoamThreshold(vals);
                    end
                    rect = 255./(1+exp(-3*pi/2*(rect-foam_th)/(255-foam_th)));
                end
                rect(~isfinite(rect)) = 0;
                IMG(:,:,ii) = uint8(max(0,min(255,rect)));
            end
            app.IMG = IMG;

            % Initialize a sensible two-class baseline: outside image/background=0,
            % valid rectified pixels=water=127. Breaking-wave regions are painted 255.
            valid = any(app.IMG > 0,3);
            app.LBL = uint8(zeros(size(valid)));
            app.LBL(valid) = 127;
            app.undoStack = {};
            app.displayDirty = true;
            app.renderDisplay();
        end

        function rgb = displayImage(app)
            switch string(app.DisplayDropDown.Value)
                case "Frame 1"; rgb = repmat(app.IMG(:,:,1),1,1,3);
                case "Frame 2"; rgb = repmat(app.IMG(:,:,2),1,1,3);
                case "Frame 3"; rgb = repmat(app.IMG(:,:,3),1,1,3);
                otherwise;      rgb = app.IMG;
            end
        end

        function renderDisplay(app)
            if isempty(app.IMG); return; end
            cla(app.UIAxes);
            imagesc(app.UIAxes,app.X,app.Y,app.displayImage());
            set(app.UIAxes,'YDir','normal');
            axis(app.UIAxes,'image');
            colormap(app.UIAxes,gray(256));
            xlabel(app.UIAxes,'Cross-shore x [m]');
            ylabel(app.UIAxes,'Alongshore y [m]');
            title(app.UIAxes,sprintf('Stack %d / %d    (video frame %d)', ...
                app.currentFrameIndex,max(1,numel(app.videoFrameIndices)-2), ...
                app.videoFrameIndices(app.currentFrameIndex+1)));
            hold(app.UIAxes,'on');
            if app.OverlayCheckBox.Value
                % Semi-transparent class colors: water=green, breaking=red.
                % Background/outside-image stays transparent so the imagery remains visible.
                water = app.LBL == 127;
                brk   = app.LBL == 255;
                RGB = zeros([size(app.LBL),3]);
                RGB(:,:,2) = double(water);
                RGB(:,:,1) = double(brk);
                RGB(:,:,3) = 0.15*double(water);
                h = imagesc(app.UIAxes,app.X,app.Y,RGB);
                alpha = 0.22*double(water) + 0.50*double(brk);
                set(h,'AlphaData',alpha);
            end
            hold(app.UIAxes,'off');
            app.displayDirty = false;
        end

        function foam_th = estimateFoamThreshold(app,vals)
            %#ok<INUSD>
            % Conservative percentile-based threshold matching the intent of
            % MAIN_FLOW_RECENT without requiring an external helper.
            vals = double(vals(:));
            vals = vals(isfinite(vals));
            if isempty(vals)
                foam_th = 128;
                return
            end
            % Use the lower half of the intensity distribution to avoid selecting
            % bright foam/sky as the reference level.
            p25 = prctile(vals,25);
            p60 = prctile(vals,60);
            foam_th = max(1,min(254,0.5*(p25+p60)));
        end

        function setClass(app,val,label)
            app.selectedClass = uint8(val);
            app.setStatus(sprintf('Annotation class: %s (%d). Draw closed regions with the Wacom pen.',label,val));
        end

        function annotateRegion(app)
            if isempty(app.IMG); return; end
            roi = drawfreehand(app.UIAxes,'Closed',true,'Smoothing',0,'Color',[1 0 0]);
            if isempty(roi) || size(roi.Position,1) < 3
                return
            end
            app.undoStack{end+1} = app.LBL;
            [xx,yy] = meshgrid(app.X,app.Y);
            inside = inpolygon(xx,yy,roi.Position(:,1),roi.Position(:,2));
            app.LBL(inside) = app.selectedClass;
            if isvalid(roi); delete(roi); end
            app.renderDisplay();
            app.setStatus(sprintf('Painted %d pixels with class %d.',nnz(inside),app.selectedClass));
        end

        function eraseRegion(app)
            if isempty(app.IMG); return; end
            roi = drawfreehand(app.UIAxes,'Closed',true,'Smoothing',0,'Color',[0 0 0]);
            if isempty(roi); return; end
            app.undoStack{end+1} = app.LBL;
            [xx,yy] = meshgrid(app.X,app.Y);
            inside = inpolygon(xx,yy,roi.Position(:,1),roi.Position(:,2));
            app.LBL(inside) = 127; % erase to water, which is safer than destroying the class mask
            if isvalid(roi); delete(roi); end
            app.renderDisplay();
        end

        function undo(app)
            if isempty(app.undoStack)
                app.setStatus('Nothing to undo.');
                return
            end
            app.LBL = app.undoStack{end};
            app.undoStack(end) = [];
            app.renderDisplay();
        end

        function clearMask(app)
            if isempty(app.IMG); return; end
            app.undoStack{end+1} = app.LBL;
            valid = any(app.IMG > 0,3);
            app.LBL = uint8(zeros(size(valid)));
            app.LBL(valid) = 127;
            app.renderDisplay();
        end

        function saveCurrent(app)
            if isempty(app.IMG); error('Load a video first.'); end
            if isempty(app.archiveRoot); error('Training-data archive directory is not initialized.'); end

            [~,base,ext] = fileparts(app.selectedVideoFile);
            frame = app.videoFrameIndices(app.currentFrameIndex+1);
            stem = sprintf('%s_Frame_%06d',base,frame);
            imageName = fullfile(app.archiveRoot,'trainingImages',[stem '.png']);
            labelName = fullfile(app.archiveRoot,'trainingLabels',[stem '.png']);
            metaName  = fullfile(app.archiveRoot,'trainingMeta',[stem '.mat']);

            if exist(imageName,'file') || exist(labelName,'file')
                choice = uiconfirm(app.UIFigure,...
                    'Training sample already exists. Overwrite it?',...
                    'Duplicate sample','Options',{'Overwrite','Cancel'},...
                    'DefaultOption','Cancel','CancelOption','Cancel');
                if ~strcmp(choice,'Overwrite'); return; end
            end

            imwrite(app.IMG,imageName,'png');
            imwrite(app.LBL,labelName,'png');

            meta = struct();
            meta.sourceVideo = app.selectedVideoFile;
            meta.videoFrameIndices = app.videoFrameIndices(app.currentFrameIndex:app.currentFrameIndex+2);
            meta.middleVideoFrame = frame;
            meta.frameRate = app.vid.FrameRate;
            meta.sampleRate = app.info.freq;
            meta.cameraID = app.cameraID;
            meta.X = app.X;
            meta.Y = app.Y;
            meta.X_res = app.info.X_res;
            meta.Y_res = app.info.Y_res;
            meta.classValues = struct('background',0,'water',127,'breakingWave',255);
            meta.enhanceImage = app.enhanceImage;
            meta.appName = 'select_CNN_training';
            meta.savedAt = datetime('now');
            meta.imageFile = imageName;
            meta.labelFile = labelName;
            save(metaName,'meta','-v7');

            app.currentImageName = imageName;
            app.currentLabelName = labelName;
            app.currentMetaName = metaName;
            app.setStatus(sprintf('Saved training sample:\n%s\n%s\n%s',imageName,labelName,metaName));
        end

        function previousStack(app)
            if isempty(app.vid); return; end
            app.currentFrameIndex = max(1,app.currentFrameIndex-1);
            app.loadStack();
        end

        function nextStack(app)
            if isempty(app.vid); return; end
            maxStart = numel(app.videoFrameIndices)-2;
            app.currentFrameIndex = min(maxStart,app.currentFrameIndex+1);
            app.loadStack();
        end

        function frameChanged(app)
            if isempty(app.vid); return; end
            maxStart = numel(app.videoFrameIndices)-2;
            app.currentFrameIndex = min(maxStart,max(1,round(app.FrameEditField.Value)));
            app.loadStack();
        end

        function displayChanged(app)
            app.renderDisplay();
        end

        function overlayChanged(app)
            app.renderDisplay();
        end

        function enhanceChanged(app)
            app.enhanceImage = logical(app.EnhanceCheckBox.Value);
            if ~isempty(app.vid); app.loadStack(); end
        end

        function startupFcn(app)
            app.UIFigure.WindowState = 'maximized';
            app.setStatus({ ...
                '1) Select your local waveIMG root directory.'; ...
                '2) Select the new video directory and camera ID.'; ...
                '3) Load a video.'; ...
                '4) Use the Wacom pen to draw regions: background, water, or breaking wave.'; ...
                '5) Review the overlay, then Save Sample.'; ...
                'Training output is written under waveIMG/trainingData/.'});
        end
    end

    methods (Access = private)

        function SelectRootButtonPushed(app,~)
            app.setupRoot();
        end

        function BrowseVideoButtonPushed(app,~)
            app.setupVideoDir();
        end

        function LoadVideoButtonPushed(app,~)
            try
                app.loadVideo();
                app.FrameEditField.Limits = [1 max(1,numel(app.videoFrameIndices)-2)];
                app.FrameEditField.Value = app.currentFrameIndex;
            catch ME
                uialert(app.UIFigure,ME.message,'Load video failed');
            end
        end

        function PreviousButtonPushed(app,~)
            app.previousStack();
            app.FrameEditField.Value = app.currentFrameIndex;
        end

        function NextButtonPushed(app,~)
            app.nextStack();
            app.FrameEditField.Value = app.currentFrameIndex;
        end

        function FrameEditFieldValueChanged(app,~)
            app.frameChanged();
        end

        function DisplayDropDownValueChanged(app,~)
            app.displayChanged();
        end

        function BackgroundButtonPushed(app,~)
            app.setClass(0,'background');
            app.annotateRegion();
        end

        function WaterButtonPushed(app,~)
            app.setClass(127,'water');
            app.annotateRegion();
        end

        function BreakingButtonPushed(app,~)
            app.setClass(255,'breaking wave');
            app.annotateRegion();
        end

        function EraseButtonPushed(app,~)
            app.eraseRegion();
        end

        function UndoButtonPushed(app,~)
            app.undo();
        end

        function ClearButtonPushed(app,~)
            app.clearMask();
        end

        function SaveButtonPushed(app,~)
            try
                app.saveCurrent();
            catch ME
                uialert(app.UIFigure,ME.message,'Save failed');
            end
        end

        function EnhanceCheckBoxValueChanged(app,~)
            app.enhanceChanged();
        end

        function OverlayCheckBoxValueChanged(app,~)
            app.overlayChanged();
        end

        function RootDirectoryEditFieldValueChanged(app,~)
            if ~isempty(app.RootDirectoryEditField.Value) && isfolder(app.RootDirectoryEditField.Value)
                app.rootDir = char(app.RootDirectoryEditField.Value);
                addpath(genpath(app.rootDir));
                app.archiveRoot = fullfile(app.rootDir,'trainingData');
                mkdir(app.archiveRoot);
                mkdir(fullfile(app.archiveRoot,'trainingImages'));
                mkdir(fullfile(app.archiveRoot,'trainingLabels'));
                mkdir(fullfile(app.archiveRoot,'trainingMeta'));
            end
        end

        function VideoDirectoryEditFieldValueChanged(app,~)
            app.videoDir = char(app.VideoDirectoryEditField.Value);
            app.updateFileList();
        end
    end

    methods (Access = private)
        function createComponents(app)
            app.UIFigure = uifigure('Visible','off');
            app.UIFigure.Position = [50 50 1500 900];
            app.UIFigure.Name = 'waveIMG CNN Training Annotation';

            app.UIAxes = uiaxes(app.UIFigure);
            app.UIAxes.Position = [330 90 1130 750];
            app.UIAxes.TickDir = 'out';
            app.UIAxes.TickLabelInterpreter = 'latex';
            app.UIAxes.FontSize = 13;

            % Data setup controls
            app.RootDirectoryEditFieldLabel = uilabel(app.UIFigure,'Position',[20 830 135 22],'Text','waveIMG root');
            app.RootDirectoryEditField = uieditfield(app.UIFigure,'text','Position',[20 805 250 25]);
            app.BrowseRootButton = uibutton(app.UIFigure,'push','Position',[275 805 35 25],'Text','...','ButtonPushedFcn',@(s,e)app.SelectRootButtonPushed(e));

            app.VideoDirectoryEditFieldLabel = uilabel(app.UIFigure,'Position',[20 765 135 22],'Text','Video directory');
            app.VideoDirectoryEditField = uieditfield(app.UIFigure,'text','Position',[20 740 250 25],'ValueChangedFcn',@(s,e)app.VideoDirectoryEditFieldValueChanged(e));
            app.BrowseVideoButton = uibutton(app.UIFigure,'push','Position',[275 740 35 25],'Text','...','ButtonPushedFcn',@(s,e)app.BrowseVideoButtonPushed(e));

            app.CameraIDEditFieldLabel = uilabel(app.UIFigure,'Position',[20 700 135 22],'Text','Camera ID');
            app.CameraIDEditField = uieditfield(app.UIFigure,'text','Position',[160 700 120 25],'Value','top21');
            app.LoadVideoButton = uibutton(app.UIFigure,'push','Position',[20 660 125 30],'Text','Load Video','ButtonPushedFcn',@(s,e)app.LoadVideoButtonPushed(e));
            app.VideoFileDropDownLabel = uilabel(app.UIFigure,'Position',[20 620 80 22],'Text','Video');
            app.VideoFileDropDown = uidropdown(app.UIFigure,'Position',[105 620 175 25],'Items',{'<select video>'},'ItemsData',{''});

            % Frame controls
            app.FrameEditFieldLabel = uilabel(app.UIFigure,'Position',[20 575 75 22],'Text','Stack #');
            app.FrameEditField = uieditfield(app.UIFigure,'numeric','Position',[100 575 60 25],'Limits',[1 Inf],'RoundFractionalValues','on','Value',1,'ValueChangedFcn',@(s,e)app.FrameEditFieldValueChanged(e));
            app.PreviousButton = uibutton(app.UIFigure,'push','Position',[170 575 55 25],'Text','<','ButtonPushedFcn',@(s,e)app.PreviousButtonPushed(e));
            app.NextButton = uibutton(app.UIFigure,'push','Position',[230 575 55 25],'Text','>','ButtonPushedFcn',@(s,e)app.NextButtonPushed(e));

            app.DisplayDropDownLabel = uilabel(app.UIFigure,'Position',[20 535 80 22],'Text','Display');
            app.DisplayDropDown = uidropdown(app.UIFigure,'Position',[105 535 175 25], ...
                'Items',{'3-frame RGB stack','Frame 1','Frame 2','Frame 3'}, ...
                'ValueChangedFcn',@(s,e)app.DisplayDropDownValueChanged(e));
            app.EnhanceCheckBox = uicheckbox(app.UIFigure,'Position',[20 500 250 25], ...
                'Text','Carini-style contrast enhancement','Value',false,'ValueChangedFcn',@(s,e)app.EnhanceCheckBoxValueChanged(e));

            % Annotation controls
            uilabel(app.UIFigure,'Position',[20 455 250 22],'Text','Wacom annotation: draw a closed region');
            app.BackgroundButton = uibutton(app.UIFigure,'push','Position',[20 415 90 30],'Text','Background','ButtonPushedFcn',@(s,e)app.BackgroundButtonPushed(e));
            app.WaterButton = uibutton(app.UIFigure,'push','Position',[115 415 75 30],'Text','Water','ButtonPushedFcn',@(s,e)app.WaterButtonPushed(e));
            app.BreakingButton = uibutton(app.UIFigure,'push','Position',[195 415 90 30],'Text','Breaking','ButtonPushedFcn',@(s,e)app.BreakingButtonPushed(e));
            app.EraseButton = uibutton(app.UIFigure,'push','Position',[20 375 90 30],'Text','Erase -> Water','ButtonPushedFcn',@(s,e)app.EraseButtonPushed(e));
            app.UndoButton = uibutton(app.UIFigure,'push','Position',[115 375 75 30],'Text','Undo','ButtonPushedFcn',@(s,e)app.UndoButtonPushed(e));
            app.ClearButton = uibutton(app.UIFigure,'push','Position',[195 375 90 30],'Text','Reset Mask','ButtonPushedFcn',@(s,e)app.ClearButtonPushed(e));

            app.BrushSizeEditFieldLabel = uilabel(app.UIFigure,'Position',[20 335 80 22],'Text','Brush size');
            app.BrushSizeEditField = uieditfield(app.UIFigure,'numeric','Position',[105 335 70 25],'Limits',[1 100],'Value',10);
            % drawfreehand is used as a closed region tool; brush size is retained
            % for future pen-brush implementation and as a visible annotation setting.

            app.OverlayCheckBox = uicheckbox(app.UIFigure,'Position',[20 300 220 25], ...
                'Text','Show breaking-wave overlay','Value',true,'ValueChangedFcn',@(s,e)app.OverlayCheckBoxValueChanged(e));

            app.SaveButton = uibutton(app.UIFigure,'push','Position',[20 245 265 45], ...
                'Text','SAVE TRAINING SAMPLE','FontWeight','bold','ButtonPushedFcn',@(s,e)app.SaveButtonPushed(e));

            app.StatusTextArea = uitextarea(app.UIFigure,'Position',[20 90 285 135],'Editable','off');

            app.UIFigure.Visible = 'on';
        end
    end

    methods (Access = public)
        function app = select_CNN_training
            createComponents(app)
            registerApp(app,app.UIFigure)
            runStartupFcn(app,@startupFcn)
            if nargout == 0
                clear app
            end
        end

        function delete(app)
            if isvalid(app.UIFigure)
                delete(app.UIFigure)
            end
        end
    end
end
