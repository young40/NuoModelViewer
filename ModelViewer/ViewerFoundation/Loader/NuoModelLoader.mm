//
//  NuoModelLoader.m
//  ModelViewer
//
//  Created by middleware on 8/26/16.
//  Copyright © 2016 middleware. All rights reserved.
//

#import "NuoModelLoader.h"

#include "NuoModelBase.h"
#include "NuoMaterial.h"
#include "NuoMeshCompound.h"

#include "tiny_obj_loader.h"



typedef std::vector<tinyobj::shape_t> ShapeVector;
typedef std::shared_ptr<ShapeVector> PShapeVector;
typedef std::map<NuoMaterial, tinyobj::shape_t> ShapeMapByMaterial;
typedef std::shared_ptr<ShapeMapByMaterial> PShapeMapByMaterial;




static void DoSplitShapes(const PShapeVector result, const tinyobj::shape_t shape)
{
    tinyobj::mesh_t mesh = shape.mesh;
    
    assert(mesh.num_face_vertices.size() == mesh.material_ids.size());
    
    size_t faceAccount = mesh.num_face_vertices.size();
    size_t i = 0;
    for (i = 0; i < faceAccount - 1; ++i)
    {
        unsigned char numPerFace1 = mesh.num_face_vertices[i];
        unsigned char numPerFace2 = mesh.num_face_vertices[i+1];
        
        int material1 = mesh.material_ids[i];
        int material2 = mesh.material_ids[i+1];
        
        assert(numPerFace1 == 3);
        assert(numPerFace2 == 3);
        
        if (numPerFace1 != numPerFace2 || material1 != material2)
        {
            tinyobj::shape_t splitShape;
            tinyobj::shape_t remainShape;
            splitShape.name = shape.name;
            remainShape.name = shape.name;
            
            std::vector<tinyobj::index_t>& addedIndices = splitShape.mesh.indices;
            std::vector<tinyobj::index_t>& remainIndices = remainShape.mesh.indices;
            addedIndices.insert(addedIndices.begin(),
                                mesh.indices.begin(),
                                mesh.indices.begin() + (i + 1) * numPerFace1);
            remainIndices.insert(remainIndices.begin(),
                                 mesh.indices.begin() + (i + 1) * numPerFace1,
                                 mesh.indices.end());
            
            std::vector<unsigned char>& addedNumberPerFace = splitShape.mesh.num_face_vertices;
            std::vector<unsigned char>& remainNumberPerFace = remainShape.mesh.num_face_vertices;
            addedNumberPerFace.insert(addedNumberPerFace.begin(),
                                      mesh.num_face_vertices.begin(),
                                      mesh.num_face_vertices.begin() + i + 1);
            remainNumberPerFace.insert(remainNumberPerFace.begin(),
                                       mesh.num_face_vertices.begin() + i + 1,
                                       mesh.num_face_vertices.end());
            
            std::vector<int>& addedMaterial = splitShape.mesh.material_ids;
            std::vector<int>& remainMaterial = remainShape.mesh.material_ids;
            addedMaterial.insert(addedMaterial.begin(),
                                 mesh.material_ids.begin(),
                                 mesh.material_ids.begin() + i + 1);
            remainMaterial.insert(remainMaterial.begin(),
                                  mesh.material_ids.begin() + i + 1,
                                  mesh.material_ids.end());
            
            result->push_back(splitShape);
            DoSplitShapes(result, remainShape);
            break;
        }
    }
    
    if (i == faceAccount - 1)
        result->push_back(shape);
}



static tinyobj::shape_t DoMergeShapes(std::vector<tinyobj::shape_t> shapes)
{
    tinyobj::shape_t result;
    result.name = shapes[0].name;
    
    for (const auto& shape : shapes)
    {
        result.mesh.indices.insert(result.mesh.indices.end(),
                                   shape.mesh.indices.begin(),
                                   shape.mesh.indices.end());
        result.mesh.material_ids.insert(result.mesh.material_ids.end(),
                                        shape.mesh.material_ids.begin(),
                                        shape.mesh.material_ids.end());
        result.mesh.num_face_vertices.insert(result.mesh.num_face_vertices.end(),
                                             shape.mesh.num_face_vertices.begin(),
                                             shape.mesh.num_face_vertices.end());
    }
    
    return result;
}




static PShapeMapByMaterial DoMergeShapesInVector(const PShapeVector result,
                                                 std::vector<tinyobj::material_t>& materials,
                                                 bool combineMaterial)
{
    typedef std::map<NuoMaterial, std::vector<tinyobj::shape_t>> ShapeMap;
    ShapeMap shapesMap;
    
    NuoMaterial nonMaterial;
    
    for (size_t i = 0; i < result->size(); ++i)
    {
        const auto& shape = (*result)[i];
        int shapeMaterial = shape.mesh.material_ids[0];
        
        if (shapeMaterial < 0)
        {
            shapesMap[nonMaterial].push_back(shape);
        }
        else
        {
            tinyobj::material_t material = materials[(size_t)shapeMaterial];
            NuoMaterial materialIndex(material, !combineMaterial);
            shapesMap[materialIndex].push_back(shape);
        }
    }
    
    result->clear();
    
    PShapeMapByMaterial shapeMapByMaterial = std::make_shared<ShapeMapByMaterial>();
    
    for (auto itr = shapesMap.begin(); itr != shapesMap.end(); ++itr)
    {
        const NuoMaterial& material = itr->first;
        std::vector<tinyobj::shape_t>& shapes = itr->second;
        shapeMapByMaterial->insert(std::make_pair(material, DoMergeShapes(shapes)));
    }
    
    return shapeMapByMaterial;
}




static PShapeMapByMaterial GetShapeVectorByMaterial(ShapeVector& shapes,
                                                    std::vector<tinyobj::material_t> &materials,
                                                    bool combineMaterial)
{
    PShapeVector result = std::make_shared<ShapeVector>();
    for (const auto& shape : shapes)
        DoSplitShapes(result, shape);
    
    PShapeMapByMaterial shapeMap;
    shapeMap = DoMergeShapesInVector(result, materials, combineMaterial);
    
    return shapeMap;
}




@implementation NuoModelLoader
{
    NSString* _basePath;
    
    tinyobj::attrib_t _attrib;
    std::vector<tinyobj::shape_t> _shapes;
    std::vector<tinyobj::material_t> _materials;
}



- (void)loadModel:(NSString*)path
{
    std::string err;
    
    _basePath = [path stringByDeletingLastPathComponent];
    _basePath = [_basePath stringByAppendingString:@"/"];
    
    _shapes.clear();
    _materials.clear();
    
    tinyobj::LoadObj(&_attrib, &_shapes, &_materials, &err, path.UTF8String, _basePath.UTF8String);
}



- (NuoMeshCompound*)createMeshsWithOptions:(NuoMeshOption*)loadOption
                                withDevice:(id<MTLDevice>)device
                          withCommandQueue:(id<MTLCommandQueue>)commandQueue
                              withProgress:(NuoProgressFunction)progress
{
    typedef std::shared_ptr<NuoModelBase> PNuoModelBase;
    
    const float loadingPortionModelBuffer = loadOption.textured ? 0.70 : 0.85;
    const float loadingPortionModelGPU = (1 - loadingPortionModelBuffer);
    
    PShapeMapByMaterial shapeMap = GetShapeVectorByMaterial(_shapes, _materials, loadOption.combineShapes);
    
    std::vector<PNuoModelBase> models;
    std::map<PNuoModelBase, NuoModelOption> modelOptions;
    std::vector<uint32> indices;
    
    unsigned long vertexNumTotal = 0;
    unsigned long vertexNumLoaded = 0;
    for (tinyobj::shape_t shape : _shapes)
         vertexNumTotal += shape.mesh.indices.size();
    
    for (const auto& shapeItr : (*shapeMap))
    {
        const NuoMaterial material(shapeItr.first);
        const tinyobj::shape_t& shape = shapeItr.second;
        
        NuoModelOption options;
        options._textured = loadOption.textured;
        options._textureEmbedMaterialTransparency = loadOption.textureEmbeddingMaterialTransparency;
        options._texturedBump = loadOption.texturedBump;
        options._basicMaterialized = loadOption.basicMaterialized;
        options._physicallyReflection = loadOption.physicallyReflection;
        
        PNuoModelBase modelBase = CreateModel(options, material, shape.name);
        
        for (size_t i = 0; i < shape.mesh.indices.size(); ++i)
        {
            tinyobj::index_t index = shape.mesh.indices[i];
            
            modelBase->AddPosition(index.vertex_index, _attrib.vertices);
            if (_attrib.normals.size())
                modelBase->AddNormal(index.normal_index, _attrib.normals);
            if (material.HasTextureDiffuse())
                modelBase->AddTexCoord(index.texcoord_index, _attrib.texcoords);
            
            int materialID = shape.mesh.material_ids[i / 3];
            if (materialID >= 0)
            {
                NuoMaterial vertexMaterial(_materials[materialID], false /* ignored */);
                modelBase->AddMaterial(vertexMaterial);
            }
        }
        
        modelBase->GenerateIndices();
        if (!_attrib.normals.size())
            modelBase->GenerateNormals();
        
        if (material.HasTextureDiffuse())
        {
            NSString* diffuseTexName = [NSString stringWithUTF8String:material.diffuse_texname.c_str()];
            NSString* diffuseTexPath = [_basePath stringByAppendingPathComponent:diffuseTexName];
            
            modelBase->SetTexturePathDiffuse(diffuseTexPath.UTF8String);
        }
        
        if (material.HasTextureOpacity())
        {
            NSString* opacityTexName = [NSString stringWithUTF8String:material.alpha_texname.c_str()];
            NSString* opacityTexPath = [_basePath stringByAppendingPathComponent:opacityTexName];
            
            modelBase->SetTexturePathOpacity(opacityTexPath.UTF8String);
        }
        
        if (material.HasTextureBump())
        {
            NSString* bumpTexName = [NSString stringWithUTF8String:material.bump_texname.c_str()];
            NSString* bumpTexPath = [_basePath stringByAppendingPathComponent:bumpTexName];
            
            modelBase->GenerateTangents();
            modelBase->SetTexturePathBump(bumpTexPath.UTF8String);
        }
        
        models.push_back(modelBase);
        modelOptions.insert(std::make_pair(modelBase, options));
        
        vertexNumLoaded += shape.mesh.indices.size();
        
        if (progress)
            progress(vertexNumLoaded / (float)vertexNumTotal * loadingPortionModelBuffer);
    }
    
    NSMutableArray<NuoMesh*>* result = [[NSMutableArray<NuoMesh*> alloc] init];
    
    size_t index = 0;
    for (auto& model : models)
    {
        NuoBox boundingBox = model->GetBoundingBox();
        
        NuoModelOption options = modelOptions[model];
        NuoMesh* mesh = CreateMesh(options, device, commandQueue, model);
        
        NuoMeshBox* meshBounding = [[NuoMeshBox alloc] init];
        meshBounding.span.x = boundingBox._spanX;
        meshBounding.span.y = boundingBox._spanY;
        meshBounding.span.z = boundingBox._spanZ;
        meshBounding.center.x = boundingBox._centerX;
        meshBounding.center.y = boundingBox._centerY;
        meshBounding.center.z = boundingBox._centerZ;
        
        mesh.boundingBoxLocal = meshBounding;
        [result addObject:mesh];
        
        if (progress)
            progress(++index / (float)models.size() * loadingPortionModelGPU + loadingPortionModelBuffer);
    }
    
    NuoMeshCompound* resultObj = [NuoMeshCompound new];
    [resultObj setMeshes:result];
    
    return resultObj;
}

@end
