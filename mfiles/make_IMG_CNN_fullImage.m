%
% get a structure with training data
trainDataPath = '/Users/derekgrimes/Library/CloudStorage/OneDrive-UNC-Wilmington/SED/Prezley/TrainingData/';
imageDir      = [trainDataPath, 'trainingImage/'];
labelDir      = [trainDataPath, 'trainingLabel/'];
%
%             background, nonFront, front
classNames = ["bckgrnd" , "nonFront" ,  "front"];
classLabel = [0         ,  127    ,  255];
pxds       = pixelLabelDatastore(labelDir,classNames,classLabel);
imds       = imageDatastore(imageDir);
%
%
%
TrainingData  = combine(imds,pxds);
%
numFiles = length(imds.Files);
Ntrain   = floor(0.75*numFiles);
perm     = randperm(numFiles);
imdsValid  = subset(TrainingData,perm(Ntrain+1:numFiles));
imdsTrain  = subset(TrainingData,perm(1:Ntrain));
%
%
% get input layer size
img = readimage(imds,perm(3));
lbl = readimage(pxds,perm(3));
[Ny,Nx,Nt] = size(img);
%
% determine the ratios of pixel classes
frac   = [0 0 0];
for ii = 1:numFiles
    lbl   = readimage(pxds,perm(ii));
    [~,class] = ismember(lbl,{'bckgrnd','nonFront','front'});
    Nbg   = numel(find(class==1));    
    Nnf   = numel(find(class==2));    
    Nn    = numel(find(class==3));    
    frac  = frac + [Nbg Nnf Nn]./(Ny*Nx);
end
unitGain = 1./frac(2);
weights = 1./frac./unitGain
%
%
numFilters = 16;
filterSize = 5;
numClasses = 3;
% Load existing:
load('~/git/waveIMG/mat_data/imgUNet_v0.mat')
imgNet0 = imgNet;
% build from scratch:
layers = [
    imageInputLayer([Ny Nx Nt])
    convolution2dLayer(filterSize,numFilters,'Padding','same')
    batchNormalizationLayer
    reluLayer()
    maxPooling2dLayer(3,'Stride',2,'Padding',[1 1])
    convolution2dLayer(filterSize,numFilters,'Padding','same')
    batchNormalizationLayer    
    reluLayer()
    transposedConv2dLayer(4,numFilters,'Stride',2,'Cropping','same');
    convolution2dLayer(1,numClasses,'Padding','same');
    batchNormalizationLayer
    softmaxLayer()
    pixelClassificationLayer('Classes',classNames,'ClassWeights',[1 1 20])
    ];
%
%
%
% 1. Apply custom geometric augmentations to your CombinedDatastore
dsTrainAug = transform(imdsTrain, @augmentImageData);

% 2. Preview one augmented batch to verify the transformations look right
sampleData = preview(dsTrainAug);
imshow(sampleData{1});
%
options = trainingOptions('sgdm',...
                          'InitialLearnRate',0.005,...'MaxEpocs', 4,...
                          'Shuffle','every-epoch',...
                          'ValidationFrequency',5,...
                          'MaxEpochs',50,...
                          'Verbose',0,...
                          'ValidationData',imdsValid,...                          
                          'ExecutionEnvironment','parallel',...                          
                          'Plots','training-progress');
%
imgNet = trainNetwork(dsTrainAug,layers,options);
% $$$ imgNet = trainNetwork(dsTrainAug,imgNet0.Layers,options);
%
% visually evaluate skill
% get input layer size
imIn = [trainDataPath,filesep,'trainingImage',filesep,'20130929_112106_B314_00408CEBCECB_01_rod13_f000005.png'];
lbIn = [trainDataPath,filesep,'trainingLabel',filesep,'20130929_112106_B314_00408CEBCECB_01_rod13_f000005.png'];
% $$$ [~,imNum]= ismember(imIn,imds.Files);
img = imread(imIn);
lbl = imread(lbIn);
lbl0 = semanticseg(img,imgNet);
act  = activations(imgNet,img,'softmax');
A = labeloverlay(img,lbl);
B = labeloverlay(img,lbl0);
figure,
subplot(1,2,1)
imshow(A)
title('Pixel Network')
subplot(1,2,2)
imshow(B)
hold on, contour(act(:,:,3),[0.5 0.5],'r')
title('Image Network')
%
%
save('../mat_data/imgNet_v9.mat','imgNet')

function dataOut = augmentImageData(dataIn)
    dataOut = dataIn;
    img = dataIn{1};
    mask = dataIn{2};
    
    tform = randomAffine2d( ...
        Rotation=[-10 10], ...
        XTranslation=[-15 15], ...
        YTranslation=[-15 15], ...
        YReflection=true, ...
        XReflection=false);
    
    rout = affineOutputView(size(img), tform, BoundsStyle="CenterOutput");
    
    % Bilinear interpolation for image, nearest-neighbor for mask
    dataOut{1} = imwarp(img, tform, OutputView=rout);
    dataOut{2} = imwarp(mask, tform, "nearest", OutputView=rout);
end